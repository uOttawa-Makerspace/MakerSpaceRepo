# frozen_string_literal: true

require "rails_helper"

# The compare-and-set of User#bump_token_version!(from_version:) against bumps made
# on OTHER connections (committed, as in production), which is what re-auth exhaustion
# relies on: of any number of callers holding the same version exactly one bumps.
RSpec.describe User, "#bump_token_version! compare-and-set under concurrency" do
  self.use_transactional_tests = false

  let!(:user) { create(:user, :regular_user) }

  after do
    ApiRefreshToken.where(user_id: user.id).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

  def in_other_connection(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }.value
  end

  DEADLINE = 10 # seconds: a missing thread fails the example instead of hanging it

  def wait_until_all_arrived(barrier, count)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
    until barrier.size >= count
      raise "barrier: not every thread arrived within #{DEADLINE}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  it "does nothing when another connection bumped between the load and the call" do
    loaded = User.find(user.id)
    version = loaded.token_version
    expect(in_other_connection { User.find(user.id).bump_token_version!(from_version: version) }).to be_truthy

    expect(loaded.bump_token_version!(from_version: version)).to be(false)
    expect(User.find(user.id).token_version).to eq(version + 1)
  end

  it "bumps exactly once for callers racing with the same version" do
    version = user.token_version
    barrier = Queue.new
    threads = Array.new(6) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          candidate = User.find(user.id)
          barrier << true
          wait_until_all_arrived(barrier, 6)
          candidate.bump_token_version!(from_version: version)
        end
      end
    end
    results = threads.map(&:value)
    expect(results.count { |r| r }).to eq(1)
    expect(User.find(user.id).token_version).to eq(version + 1)
  end

  it "returns false (compare-and-set) for a soft-deleted row; the unconditional bump still bumps it" do
    loaded = User.find(user.id)
    in_other_connection { User.find(user.id).soft_delete! }
    version = User.unscoped.find(user.id).token_version

    expect(loaded.bump_token_version!(from_version: loaded.token_version)).to be(false)
    expect(User.unscoped.find(user.id).token_version).to eq(version)
    loaded.bump_token_version!
    expect(User.unscoped.find(user.id).token_version).to eq(version + 1)
  end

  it "raises RecordNotFound without a version when the row is gone" do
    loaded = User.find(user.id)
    User.unscoped.where(id: user.id).delete_all
    expect { loaded.bump_token_version! }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "admin_lock! on a soft-deleted user succeeds and bumps" do
    in_other_connection { User.find(user.id).soft_delete! }
    version = User.unscoped.find(user.id).token_version
    User.unscoped.find(user.id).admin_lock!
    row = User.unscoped.find(user.id)
    expect([row.locked, row.deleted, row.token_version]).to eq([true, true, version + 1])
  end

  it "two soft deletes racing both succeed (no RecordNotFound), each bumping once" do
    version = user.token_version
    barrier = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          candidate = User.find(user.id)
          barrier << true
          wait_until_all_arrived(barrier, 2)
          candidate.soft_delete!
          true
        end
      end
    end
    expect(threads.map(&:value)).to eq([true, true])
    row = User.unscoped.find(user.id)
    expect([row.deleted, row.token_version]).to eq([true, version + 2])
  end

  it "returns false for a row that is gone" do
    loaded = User.find(user.id)
    User.unscoped.where(id: user.id).delete_all
    expect(loaded.bump_token_version!(from_version: loaded.token_version)).to be(false)
  end

  it "soft_delete! still bumps (deleted is set in the same UPDATE) and kills the refresh tokens" do
    token = ApiRefreshToken.issue!(user)
    version = user.token_version
    User.find(user.id).soft_delete!
    row = User.unscoped.find(user.id)
    expect([row.deleted, row.token_version]).to eq([true, version + 1])
    expect(token.reload.usable?).to be(false)
    expect(token.revoked_at).to be_present
  end

  it "closes the cable before the refresh-token bookkeeping, which is best effort and reported" do
    order = []
    loaded = User.find(user.id)
    allow(loaded).to receive(:disconnect_cable!) { order << :cable }
    allow(ApiRefreshToken).to receive(:revoke_all_for!) do
      order << :tokens
      raise "boom"
    end
    expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), handled: true)
    loaded.bump_token_version!
    expect(order).to eq(%i[cable tokens])
  end

  it "store_new_password! fails, and writes nothing, when a revocation committed since the load" do
    loaded = User.find(user.id)
    digest = loaded.password
    version = loaded.token_version
    in_other_connection { User.find(user.id).bump_token_version! }

    expect { loaded.store_new_password!("Brand-new-pw-123!") }.to raise_error(ActiveRecord::StaleObjectError)
    row = User.find(user.id)
    expect([row.token_version, row.password]).to eq([version + 1, digest])
  end

  it "store_new_password! leaves the instance clean (not dirty, old password and version) after a StaleObjectError" do
    loaded = User.find(user.id)
    digest = loaded.password
    version = loaded.token_version
    in_other_connection { User.find(user.id).bump_token_version! }

    expect { loaded.store_new_password!("Brand-new-pw-123!") }.to raise_error(ActiveRecord::StaleObjectError)
    expect(loaded).not_to be_changed
    expect([loaded.password, loaded.token_version]).to eq([digest, version])
  end
end
