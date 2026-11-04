# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see rfid_link_concurrency_spec). Deleting and
# restoring accounts take a transaction advisory lock and then re-read the user under a row lock,
# so a second request for the same account finds the work done and does not repeat it.
RSpec.describe User, ".delete_account! under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:admin) { create(:user, :admin) }
  let!(:first) { create(:user, :regular_user) }
  let!(:second) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: first) }

  before { repo.users << [first, second] }

  after do
    Repository.unscoped.where(id: repo.id).each do |r|
      r.photos.each { |photo| photo.image.purge }
      r.destroy
    end
    User.unscoped.where(id: [admin.id, first.id, second.id]).delete_all
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

  # Thread 1 deletes the user and pauses inside the work. Thread 2 deletes the same user from a
  # copy loaded before: it waits for thread 1, then finds the user already deleted and returns
  # without repeating the handover or bumping the token version again.
  it "two concurrent deletes of one user do the work once" do
    one_thread = nil
    paused = Queue.new
    resume = Queue.new
    handovers = Queue.new
    allow(Repository).to receive(:release_owned_by!).and_wrap_original do |original, *args|
      handovers << true
      if Thread.current == one_thread
        one_thread = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end
    version = first.token_version
    stale_copy = User.find(first.id)

    one = in_thread do
      one_thread = Thread.current
      User.delete_account!(User.find(first.id))
    end
    ThreadPause.await(paused)
    two = in_thread { User.delete_account!(stale_copy) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results).to eq([true, false])
    expect(handovers.size).to eq(1)
    gone = User.unscoped.find(first.id)
    expect(gone.deleted).to be(true)
    expect(gone.token_version).to eq(version + 1)
    expect(Repository.find(repo.id).user_id).to eq(second.id)
  end

  it "two concurrent restores of one user do the work once" do
    first.update_columns(deleted: true)
    Repository.unscoped.where(id: repo.id).update_all(deleted: true)
    calls = Queue.new
    allow(Repository).to receive(:restore_hidden_for!).and_wrap_original do |original, *args|
      calls << true
      original.call(*args)
    end
    results = Array.new(2) { in_thread { User.restore_account!(User.unscoped.find(first.id)) } }.map(&:value)
    expect(results.grep(StandardError)).to be_empty
    expect(results.sort_by(&:to_s)).to eq([false, true])
    expect(calls.size).to eq(1)
    expect(User.find(first.id).deleted).to be(false)
  end
end
