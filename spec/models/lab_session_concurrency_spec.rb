# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see rfid_tap_concurrency_spec).
RSpec.describe LabSession, "sign in under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:space) { create(:space) }
  let!(:user) { create(:user, :regular_user) }

  after do
    LabSession.where(user_id: user.id).delete_all
    User.unscoped.where(id: user.id).delete_all
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

  # Thread 1 parks after it created the session and before it commits. Thread 2 signs the same user
  # in: with the user lock it waits and then finds the session; without it, it opens a second one.
  it "two simultaneous sign ins of one user open one session" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(LabSession).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
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
      LabSession.sign_in(user, space)
    end
    ThreadPause.await(paused)
    two = in_thread { LabSession.sign_in(user, space) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    expect(blocked_backends).to be_positive
    resume << true

    expect([one.value, two.value]).to contain_exactly(true, false)
    expect(LabSession.where(user_id: user.id).count).to eq(1)
  end
end
