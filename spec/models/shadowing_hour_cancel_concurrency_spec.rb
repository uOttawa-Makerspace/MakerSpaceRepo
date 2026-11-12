# frozen_string_literal: true

require "rails_helper"

# The job that creates a shift's Google event and the cancelling of the shift both work on the shift's row lock.
# Without it, a cancel that ran between the job reading the shift and inserting the event removed nothing
# (Google had no event yet), destroyed the shift, and the job then left an event nobody removes.
RSpec.describe ShadowingHour, "creating the event while the shift is cancelled", type: :model do
  self.use_transactional_tests = false

  let!(:space) { create(:space, name: "Makerspace") }
  let!(:volunteer) { create(:user) }
  let!(:shift) { create(:shadowing_hour, user: volunteer, space: space, event_id: "abc123") }
  let(:log) { Queue.new }

  after do
    described_class.where(id: shift.id).delete_all
    Space.where(id: space.id).delete_all
    User.unscoped.where(id: volunteer.id).delete_all
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

  it "makes the cancel wait until the event exists, so it removes it" do
    paused = Queue.new
    resume = Queue.new
    allow(described_class).to receive(:create_event) do
      paused << true
      resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      log << :inserted
    end
    allow(described_class).to receive(:delete_event) { log << :deleted }

    creating = in_thread { described_class.find(shift.id).publish_to_calendar }
    ThreadPause.await(paused)
    cancelling = in_thread { described_class.find(shift.id).cancel }
    deadline = Time.current + 5
    Thread.pass while blocked_backends.zero? && Time.current < deadline
    resume << true

    creating.value
    expect(cancelling.value).to eq(:removed)
    expect(Array.new(log.size) { log.pop }).to eq(%i[inserted deleted])
    expect(described_class.exists?(shift.id)).to be(false)
  end

  it "makes the job skip a shift that was cancelled first" do
    expect(described_class).not_to receive(:create_event)
    stale = described_class.find(shift.id)
    allow(described_class).to receive(:delete_event)
    described_class.find(shift.id).cancel
    expect(stale.publish_to_calendar).to be_nil
  end
end
