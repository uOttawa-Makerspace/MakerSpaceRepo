# frozen_string_literal: true

require "rails_helper"

# Two simultaneous assigns or revokes of the same key, on real second connections with committed
# data. The first request parks holding the key row lock; the second must block on it, then is
# refused once it sees the key's new state.
RSpec.describe Key, "assign and revoke under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:space) { create(:space) }
  let!(:holder) { create(:user, :staff) }
  let!(:supervisor) { create(:user, :admin) }
  let!(:key) { create(:key, :regular_key_type, :inventory_status, space: space, number: 31) }
  let(:attrs) { { supervisor_id: supervisor.id } }

  after do
    KeyTransaction.where(key_id: key.id).delete_all
    Key.where(id: key.id).delete_all
    User.unscoped.where(id: [holder.id, supervisor.id]).delete_all
    space.destroy
  end

  def wait_until_blocked_on_lock(release, timeout: 5)
    deadline = Time.current + timeout
    loop do
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
      ).to_i
      return if blocked.positive?
      (release << true; raise "no backend became blocked") if Time.current > deadline

      Thread.pass
    end
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  # Runs the first request holding the key lock until released, starts the second, and returns both outcomes.
  def race(&request)
    paused = Queue.new
    resume = Queue.new
    first = in_thread do
      Key.transaction do
        Key.find(key.id).tap(&:lock!)
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        request.call(Key.find(key.id))
      end
      :done
    end
    ThreadPause.await(paused)
    second = in_thread { request.call(Key.find(key.id)) }
    wait_until_blocked_on_lock(resume)
    resume << true
    [first.value, second.value]
  end

  it "two simultaneous assigns: one wins, the other is refused, one open transaction exists" do
    first, second = race { |k| k.assign_to!(holder, attrs, 20) }

    expect(first).to eq(:done)
    expect(second).to be_a(Key::StateError)
    expect(KeyTransaction.where(key_id: key.id).not_returned.count).to eq(1)
    expect(Key.find(key.id)).to be_status_held
  end

  it "two simultaneous revokes: one wins, the other is refused, one transaction is closed" do
    key.assign_to!(holder, attrs, 0)
    first, second = race(&:revoke!)

    expect(first).to eq(:done)
    expect(second).to be_a(Key::StateError)
    expect(KeyTransaction.where(key_id: key.id).returned.count).to eq(1)
    expect(KeyTransaction.where(key_id: key.id).not_returned.count).to eq(0)
    expect(Key.find(key.id)).to be_status_inventory
  end
end
