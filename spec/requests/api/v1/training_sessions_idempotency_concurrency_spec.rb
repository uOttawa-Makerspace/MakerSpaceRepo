# frozen_string_literal: true

require "rails_helper"

# Two real requests on their own connections (see spec/models/training_session_certify_concurrency_spec.rb),
# deterministic interleaving: the first request records its key and pauses before committing; the second,
# with the same key, waits on the unique index and then answers with the first one's response.
RSpec.describe "POST /api/v1/training_sessions with one Idempotency-Key, twice at once", type: :request do
  self.use_transactional_tests = false

  let!(:staff) { create(:user, :staff) }
  let!(:space) { create(:space) }
  let!(:training) { create(:training, spaces: [space]) }
  let!(:assignment) { StaffSpace.create!(user: staff, space: space) }
  let(:key) { "concurrent-#{SecureRandom.uuid}" }
  let(:payload) { { space_id: space.id, training_id: training.id, level: "Beginner" }.to_json }

  after do
    ApiIdempotencyKey.where(user_id: staff.id).delete_all
    StaffSpace.where(user_id: staff.id).delete_all
    TrainingSession.unscoped.where(user_id: staff.id).delete_all
    training.spaces.clear
    [training, space].each { |r| r.class.unscoped.where(id: r.id).delete_all }
    Skill.where(id: training.skill_id).delete_all
    User.unscoped.where(id: staff.id).delete_all
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  def post_create
    Rack::MockRequest.new(Rails.application).post(
      "/api/v1/training_sessions",
      input: payload,
      "HTTP_HOST" => "www.example.com",
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{ApiAccessToken.issue(staff).first}",
      "HTTP_IDEMPOTENCY_KEY" => key
    )
  end

  it "creates one session and answers both requests with it" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(ApiIdempotencyKey).to receive(:insert).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do
        if Thread.current == first
          first = nil
          paused << true
          resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        end
      end
    end

    one = in_thread do
      first = Thread.current
      post_create
    end
    ThreadPause.await(paused)
    two = in_thread { post_create }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    # the second request must really wait on the first one's key, or the race is not exercised
    expect(blocked_backends).to be_positive
    resume << true

    responses = [one.value, two.value]
    expect(responses.grep(StandardError)).to be_empty
    expect(responses.map(&:status)).to eq([201, 201])
    ids = responses.map { |r| JSON.parse(r.body)["id"] }
    expect(ids.uniq.size).to eq(1)
    expect(TrainingSession.where(user_id: staff.id).pluck(:id)).to eq([ids.first])
    expect(ApiIdempotencyKey.where(user_id: staff.id, key: key).count).to eq(1)
  end
end
