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

  it "mails the month once: a second run that starts while the first is still sending returns without sending" do
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
        two.join(ThreadPause::AWAIT_TIMEOUT)
        expect(two).not_to be_alive
        expect(ActionMailer::Base.deliveries).to be_empty
        expect(Setting.get("cdel_report_sent:2026-09")).to start_with("claimed:")
      ensure
        resume << true
        [one, two].compact.each { |t| t.join(ThreadPause::PARKED_TIMEOUT) }
      end
    end

    expect([one.value, two.value]).not_to include(an_instance_of(StandardError))
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(Setting.get("cdel_report_sent:2026-09")).to eq("sent")
  end
end
