# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see training_session_certify_concurrency_spec).
RSpec.describe GoogleCalendar::WebhookRegistrar, "overlapping runs", type: :service do
  self.use_transactional_tests = false

  let(:watch_url) { "https://www.googleapis.com/calendar/v3/calendars/primary/events/watch" }
  let(:stop_url) { "https://www.googleapis.com/calendar/v3/channels/stop" }

  let(:authorizer) { Class.new { def apply!(headers) = headers["Authorization"] = "Bearer test-token" }.new }

  before do
    GoogleCalendarChannel.delete_all
    allow(SubSpaceBooking).to receive(:authorizer).and_return(authorizer)
  end

  after { GoogleCalendarChannel.delete_all }

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

  it "serialises two registrations and leaves exactly one live channel: the newest" do
    paused = Queue.new
    resume = Queue.new
    first = nil
    calls = 0
    lock = Mutex.new
    stub_request(:post, watch_url).to_return do
      n = lock.synchronize { calls += 1 }
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "chan-#{n}", resourceId: "res-#{n}", expiration: (((Time.current + 7.days).to_f) * 1000).to_i.to_s }.to_json }
    end
    stub_request(:post, stop_url).to_return(status: 204, body: "")

    one = two = nil
    begin
      one = in_thread do
        first = Thread.current
        described_class.register!
      end
      ThreadPause.await(paused, "the first registration")
      two = in_thread { described_class.register! }
      deadline = Time.current + 5
      Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
      expect(two).to be_alive # waiting on the advisory lock, not running alongside the first
    ensure
      resume << true
      [one, two].compact.each { |t| t.join(ThreadPause::AWAIT_TIMEOUT) }
    end

    expect([one.value, two.value].grep(StandardError)).to be_empty
    expect(GoogleCalendarChannel.pluck(:channel_id)).to eq(["chan-2"])
    expect(a_request(:post, stop_url).with { |r| JSON.parse(r.body)["id"] == "chan-1" }).to have_been_made.once
    expect(a_request(:post, stop_url)).to have_been_made.once
  end
end
