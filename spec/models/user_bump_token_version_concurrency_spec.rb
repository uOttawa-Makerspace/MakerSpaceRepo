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
          sleep 0.01 until barrier.size >= 6
          candidate.bump_token_version!(from_version: version)
        end
      end
    end
    results = threads.map(&:value)
    expect(results.count { |r| r }).to eq(1)
    expect(User.find(user.id).token_version).to eq(version + 1)
  end
end
