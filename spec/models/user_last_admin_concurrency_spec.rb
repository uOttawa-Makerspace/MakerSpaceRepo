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

RSpec.describe User, "last-admin guard locking", type: :model do
  self.use_transactional_tests = false

  # plain is created first, so its id is lower than every admin's
  let!(:plain) { create(:user) }
  let!(:admin_a) { create(:user, :admin) }
  let!(:admin_b) { create(:user, :admin) }

  after { User.unscoped.where(id: [plain.id, admin_a.id, admin_b.id]).delete_all }

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

  def statements_of
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      seen << payload[:sql] if payload[:sql].match?(/FOR UPDATE/i)
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "a promotion locks the admin rows, then its targets, both in id order (the one global order)" do
    statements = statements_of { User.change_roles!([plain.id, admin_b.id], "admin") }
    expect(statements.size).to eq(2)
    expect(statements.first).to match(/"role" = \$\d+ ORDER BY "users"."id" ASC FOR UPDATE/)
    expect(statements.second).to match(/"users"."id" IN \(.*ORDER BY "users"."id" ASC FOR UPDATE/m)
  end

  it "a demotion locks in the same order" do
    statements = statements_of { User.change_roles!([plain.id, admin_b.id], "staff") }
    expect(statements.first).to match(/"role" = \$\d+ ORDER BY "users"."id" ASC FOR UPDATE/)
    expect(statements.second).to match(/"users"."id" IN \(.*ORDER BY "users"."id" ASC FOR UPDATE/m)
  end

  it "a promotion racing a demotion of the same users finishes without a deadlock" do
    demoter = nil
    paused = Queue.new
    resume = Queue.new
    first_call = true
    allow_any_instance_of(User).to receive(:change_role!).and_wrap_original do |original, *args|
      if Thread.current == demoter && first_call
        first_call = false
        paused << true
        resume.pop
      end
      original.call(*args)
    end

    # admin_a stays, so demoting [plain (not an admin), admin_b] is allowed
    demotion = in_thread do
      demoter = Thread.current
      User.change_roles!([plain.id, admin_b.id], "staff")
    end
    paused.pop
    promotion = in_thread { User.change_roles!([plain.id, admin_b.id], "admin") }
    promotion.join(1) # it either waits on the demotion's locks or is already done
    resume << true

    results = [demotion.value, promotion.value]
    expect(results.grep(StandardError)).to be_empty
    expect(User.where(id: [plain.id, admin_b.id]).pluck(:role).uniq.size).to eq(1)
  end
end

RSpec.describe User, "last-admin guard vs a role change between check and write", type: :model do
  self.use_transactional_tests = false

  let!(:target) { create(:user) }          # not an admin when the guard starts
  let!(:admin_a) { create(:user, :admin) } # the only admin

  after { User.unscoped.where(id: [target.id, admin_a.id]).delete_all }

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  # Pauses the given thread just BEFORE it executes its first row-locking statement
  # (nothing is held yet in the fixed code; in the old code the "is an admin
  # affected?" pre-check has already run and said no).
  def pause_before_first_lock(thread_getter, paused, resume)
    done = false
    subscriber = Object.new
    subscriber.define_singleton_method(:start) do |_name, _id, payload|
      next if done || Thread.current != thread_getter.call || !payload[:sql].to_s.match?(/FOR UPDATE/i)

      done = true
      paused << true
      resume.pop
    end
    subscriber.define_singleton_method(:finish) { |*| }
    ActiveSupport::Notifications.subscribe("sql.active_record", subscriber)
  end

  # T1 runs `guard` on a non-admin and is held before its first lock. T2 promotes the
  # target, T3 demotes the only other admin (allowed: the target is a usable admin),
  # both commit. Then T1 continues.
  def interleave(&guard)
    t1 = nil
    paused = Queue.new
    resume = Queue.new
    subscriber = pause_before_first_lock(-> { t1 }, paused, resume)
    t1 = in_thread { guard.call }
    paused.pop
    promoted = in_thread { User.change_roles!([target.id], "admin") }.value
    demoted = in_thread { User.change_roles!([admin_a.id], "staff") }.value
    resume << true
    [t1.value, promoted, demoted]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "a demotion of a user promoted meanwhile cannot take away the last usable admin" do
    demotion, promoted, demoted = interleave { User.change_roles!([target.id], "regular_user") }
    expect(promoted).not_to be_a(StandardError)
    expect(demoted).not_to be_a(StandardError)
    expect(demotion).to be_a(User::LastAdminError)
    expect(User.usable_admins.where(id: [target.id, admin_a.id]).count).to eq(1)
  end

  it "an admin lock toggle of a user promoted meanwhile cannot lock the last usable admin" do
    toggle = lambda do
      User.guarding_last_admin!([target.id], message: User::LAST_ADMIN_LOCK_MESSAGE,
                                             only_if: -> { !target.lock!.locked }) do
        target.locked ? target.admin_unlock! : target.admin_lock!
      end
    end
    result, promoted, demoted = interleave(&toggle)
    expect(promoted).not_to be_a(StandardError)
    expect(demoted).not_to be_a(StandardError)
    expect(result).to be_a(User::LastAdminError)
    expect(User.usable_admins.where(id: [target.id, admin_a.id]).count).to eq(1)
  end
end
