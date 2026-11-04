# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see rfid_link_concurrency_spec). Deleting an
# account locks the user, then the repositories it owns and a candidate member for each. Two
# deletions of co-members would take those locks in opposite orders and deadlock, so they run one
# at a time (User.serialising_account_deletion).
RSpec.describe User, ".delete_account! under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:admin) { create(:user, :admin) }
  let!(:first) { create(:user, :regular_user) }
  let!(:second) { create(:user, :regular_user) }
  let!(:third) { create(:user, :regular_user) }
  let!(:first_repo) { create(:repository, owner: first) }
  let!(:second_repo) { create(:repository, owner: second) }

  before do
    [first_repo, second_repo].each { |repo| repo.users << [first, second, third] }
  end

  after do
    Repository.unscoped.where(id: [first_repo.id, second_repo.id]).each do |repo|
      repo.photos.each { |photo| photo.image.purge }
      repo.destroy
    end
    User.unscoped.where(id: [admin.id, first.id, second.id, third.id]).delete_all
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

  # Thread 1 deletes the first user and pauses with its locks held, before it hands anything over.
  # Thread 2 deletes the second user meanwhile. Without the advisory lock thread 2 takes its own
  # user lock and then waits for the first user's row, while thread 1, once resumed, waits for the
  # second user's row: a deadlock. With it thread 2 waits for thread 1 to commit, then sees the
  # first user as deleted, so neither repository goes to a deleted member.
  it "deletes two co-members at once without a deadlock and hands both repositories to the remaining member" do
    one_thread = nil
    paused = Queue.new
    resume = Queue.new
    allow(Repository).to receive(:release_owned_by!).and_wrap_original do |original, *args|
      if Thread.current == one_thread
        one_thread = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end

    one = in_thread do
      one_thread = Thread.current
      User.delete_account!(User.find(first.id))
    end
    ThreadPause.await(paused)
    two = in_thread { User.delete_account!(User.find(second.id)) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(User.unscoped.where(id: [first.id, second.id]).pluck(:deleted)).to eq([true, true])
    expect(Repository.where(id: [first_repo.id, second_repo.id]).pluck(:user_id)).to eq([third.id, third.id])
  end
end
