# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleavings (no sleeps for ordering:
# the main thread waits until Postgres reports the other backend blocked on a lock).
RSpec.describe ApiRefreshToken, "concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:user) { create(:user) }

  after do
    ApiRefreshToken.where(user_id: user.id).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

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

  it "logout racing a rotation cannot leave the successor live" do
    token = described_class.issue!(user)
    paused = Queue.new
    resume = Queue.new
    # Rotation A: holds T's lock and pauses right before inserting the successor.
    allow(described_class).to receive(:issue!).and_wrap_original do |original, *args, **kwargs|
      paused << true
      resume.pop
      original.call(*args, **kwargs)
    end

    rotation = in_thread { described_class.find(token.id).rotate! }
    paused.pop
    logout = in_thread { described_class.revoke_family!(token.family_id) }
    wait_until_blocked_on_lock
    resume << true

    [rotation, logout].each { |t| expect(t.value).not_to be_a(StandardError) }
    expect(described_class.where(family_id: token.family_id, revoked_at: nil)).to be_empty
  end
end
