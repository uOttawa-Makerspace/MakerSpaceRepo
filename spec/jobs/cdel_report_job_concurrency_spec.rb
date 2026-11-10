# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see webhook_registrar_concurrency_spec).
RSpec.describe CdelReportJob, "overlapping runs", type: :job do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  let(:zone) { Time.find_zone("America/New_York") }

  before do
    ActionMailer::Base.deliveries.clear
    Setting.where(key: "cdel_report_sent:2026-09").delete_all
  end

  after { Setting.where(key: "cdel_report_sent:2026-09").delete_all }

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

  it "mails the month once when a second run starts while the first is still sending" do
    paused = Queue.new
    resume = Queue.new
    first = nil
    allow(MsrMailer).to receive(:send_cdel_monthly_report).and_wrap_original do |original, *args, **kwargs|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args, **kwargs)
    end

    one = two = nil
    travel_to(zone.local(2026, 11, 5, 12, 0)) do
      begin
        one = in_thread do
          first = Thread.current
          described_class.perform_now(month: "2026-09")
        end
        ThreadPause.await(paused, "the first run")
        two = in_thread { described_class.perform_now(month: "2026-09") }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ThreadPause::AWAIT_TIMEOUT
        Thread.pass until blocked_backends.positive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        expect(blocked_backends).to be_positive
      ensure
        resume << true
        [one, two].compact.each { |t| t.join(ThreadPause::PARKED_TIMEOUT) }
      end
    end

    expect([one.value, two.value]).not_to include(an_instance_of(StandardError))
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(Setting.get("cdel_report_sent:2026-09")).to be_present
  end
end
