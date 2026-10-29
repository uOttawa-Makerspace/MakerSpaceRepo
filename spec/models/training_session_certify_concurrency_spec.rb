# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see user_last_admin_concurrency_spec).
RSpec.describe TrainingSession, "#certify_trainees! under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:trainer) { create(:user, :admin) }
  let!(:space) { create(:space) }
  let!(:training) { create(:training) }
  let!(:trainees) { create_list(:user, 2) }
  let!(:session) do
    create(:training_session, user: trainer, space: space, training: training, level: "Beginner", users: trainees)
  end

  after do
    Certification.where(user_id: trainees.map(&:id)).delete_all
    session.users.clear
    TrainingSession.unscoped.where(id: session.id).delete_all
    [training, space].each { |r| r.class.unscoped.where(id: r.id).delete_all }
    User.unscoped.where(id: trainees.map(&:id) + [trainer.id]).delete_all
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

  # Thread 1 pauses after its first duplicate check, before creating anything. Thread 2 then
  # certifies the same session: with the row lock it blocks (until thread 1 commits); without
  # it, it runs to completion right away and thread 1 later creates a second set.
  it "two concurrent certifications of one session leave exactly one active certification per trainee" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    # pause right after the first "already certified?" answer (still "no"), before any create
    allow(Certification).to receive(:held_by).and_wrap_original do |original, *args|
      original.call(*args).tap do |relation|
        relation.define_singleton_method(:exists?) do |*a|
          super(*a).tap do
            if Thread.current == first
              first = nil
              paused << true
              resume.pop
            end
          end
        end
      end
    end

    one = in_thread do
      first = Thread.current
      TrainingSession.find(session.id).certify_trainees!
    end
    paused.pop
    two = in_thread { TrainingSession.find(session.id).certify_trainees! }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(Certification.where(user_id: trainees.map(&:id)).group(:user_id).count.values).to eq([1, 1])
    expect(results.map(&:duplicates).sort).to eq([0, 2])
  end
end
