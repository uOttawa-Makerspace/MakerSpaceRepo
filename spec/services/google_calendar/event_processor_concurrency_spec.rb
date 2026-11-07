# frozen_string_literal: true

require "rails_helper"

# Two syncs of the same new event at once: the unique index on google_booking_id lets one insert win, and the
# other updates that booking, so the event is mirrored once, with one approved status.
RSpec.describe GoogleCalendar::EventProcessor, "under concurrency", :booking_clock do
  include Chunk18GoogleHelpers

  self.use_transactional_tests = false

  let!(:approved) { create(:booking_status, :approved) }
  let!(:space) { create(:space) }
  let!(:stm124) { create(:sub_space, name: "STM 124", space: space) }
  let!(:creator) { create(:user, :regular_user, email: "creator@example.test") }

  after do
    ids = SubSpaceBooking.where(google_booking_id: "race-evt").pluck(:id)
    SubSpaceBooking.where(id: ids).update_all(sub_space_booking_status_id: nil)
    SubSpaceBookingStatus.where(sub_space_booking_id: ids).delete_all
    SubSpaceBooking.where(id: ids).delete_all
    stm124.destroy
    space.destroy
    approved.destroy
    User.unscoped.where(id: creator.id).delete_all
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

  it "mirrors the event once when a second sync inserts it while the first has not committed" do
    paused = Queue.new
    resume = Queue.new
    first_done = Concurrent::AtomicBoolean.new(false)
    allow(SubSpaceBookingStatus).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      if first_done.make_true
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args, **kwargs)
    end

    first = in_thread { described_class.process(c18_gcal_event(id: "race-evt", summary: "First")) }
    ThreadPause.await(paused)
    second = in_thread { described_class.process(c18_gcal_event(id: "race-evt", summary: "Second")) }
    # The example's clock is frozen, so the wait is bounded on the monotonic clock.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Thread.pass while blocked_backends.zero? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    resume << true

    expect([first.value, second.value].grep(StandardError)).to be_empty
    bookings = SubSpaceBooking.where(google_booking_id: "race-evt")
    expect(bookings.count).to eq(1)
    expect(bookings.first.name).to eq("Second")
    expect(SubSpaceBookingStatus.where(sub_space_booking_id: bookings.first.id).count).to eq(1)
    expect(bookings.first.sub_space_booking_status_id).to be_present
  end
end
