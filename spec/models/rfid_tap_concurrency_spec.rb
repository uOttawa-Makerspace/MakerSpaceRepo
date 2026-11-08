# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see rfid_link_concurrency_spec).
# RfidTap locks the card owner's row for the toggle, so two taps of one user run one after the
# other: the second sees the session the first opened instead of opening another.
RSpec.describe RfidTap, "under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:space) { create(:space) }
  let!(:owner) { create(:user, :regular_user) }
  let!(:rfid) { create(:rfid, user: owner) }

  after do
    TapBoxLog.where(user_id: owner.id).delete_all
    LabSession.where(user_id: owner.id).delete_all
    Rfid.where(id: rfid.id).delete_all
    User.unscoped.where(id: owner.id).delete_all
    Space.where(id: space.id).delete_all
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

  def tap_in = described_class.call(card: rfid.card_number, space: space, mac_address: nil)

  # Thread 1 parks inside the toggle, after it opened the session and before it commits. Thread 2
  # taps the same card: with the user lock it waits for thread 1 to commit and then finds the
  # session (a repeat); without it, it sees no session and opens a second one.
  it "two simultaneous taps of one card open one session" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(LabSession).to receive(:create_session).and_wrap_original do |original, *args, **kwargs|
      created = original.call(*args, **kwargs)
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      created
    end

    one = in_thread do
      first = Thread.current
      tap_in
    end
    ThreadPause.await(paused)
    two = in_thread { tap_in }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    expect(blocked_backends).to be_positive
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results.map(&:outcome)).to eq(%i[sign_in sign_in])
    expect(LabSession.where(user_id: owner.id).active.count).to eq(1)
    expect(LabSession.where(user_id: owner.id).count).to eq(1)
  end
end
