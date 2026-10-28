# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (the main thread waits until
# Postgres reports the other backend blocked on a lock; no sleeps for ordering).
RSpec.describe User, "last-admin guard under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:admin_a) { create(:user, :admin) }
  let!(:admin_b) { create(:user, :admin) }

  after { User.unscoped.where(id: [admin_a.id, admin_b.id]).delete_all }

  def wait_until_blocked_on_lock(timeout: 5)
    deadline = Time.current + timeout
    loop do
      blocked = ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
      ).to_i
      return if blocked.positive?
      raise "no backend became blocked" if Time.current > deadline

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

  # Thread 1 demotes admin A and pauses before committing; thread 2 then tries to
  # lock/delete admin B. Without the shared admin-row lock, B's check would still see
  # A as an admin and leave zero usable admins.
  def race(&second_action)
    paused = Queue.new
    resume = Queue.new
    allow_any_instance_of(User).to receive(:change_role!).and_wrap_original do |original, *args|
      paused << true
      resume.pop
      original.call(*args)
    end

    demotion = in_thread { User.change_roles!([admin_a.id], "staff") }
    paused.pop
    second = in_thread(&second_action)
    wait_until_blocked_on_lock
    resume << true
    [demotion.value, second.value]
  end

  it "a demotion racing an admin lock cannot leave zero usable admins" do
    demotion, lock = race do
      User.guarding_last_admin!([admin_b.id], message: User::LAST_ADMIN_LOCK_MESSAGE) { User.find(admin_b.id).admin_lock! }
    end
    expect(demotion).not_to be_a(StandardError)
    expect(lock).to be_a(User::LastAdminError)
    expect(lock.message).to eq(User::LAST_ADMIN_LOCK_MESSAGE)
    expect(User.usable_admins.where(id: [admin_a.id, admin_b.id]).count).to eq(1)
  end

  it "a demotion racing a delete cannot leave zero usable admins" do
    demotion, deletion = race do
      User.guarding_last_admin!([admin_b.id]) { User.find(admin_b.id).soft_delete! }
    end
    expect(demotion).not_to be_a(StandardError)
    expect(deletion).to be_a(User::LastAdminError)
    expect(User.usable_admins.where(id: [admin_a.id, admin_b.id]).count).to eq(1)
  end
end
