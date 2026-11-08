# frozen_string_literal: true

require "rails_helper"

# Two simultaneous requests that both take back the same like, remove the same vote or switch it the same way:
# the row is locked first, so only one of them reports a change (and is the only one that counts it).
RSpec.describe "taking back likes and votes under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:owner) { create(:user, :regular_user) }
  let!(:fan) { create(:user, :regular_user) }
  let!(:repo) { create(:repository, owner: owner, users: [owner]) }
  let!(:comment) { create(:comment, repository: repo, user: owner, username: owner.username) }

  after do
    Like.where(repository_id: repo.id).delete_all
    Upvote.where(comment_id: comment.id).delete_all
    Comment.where(id: comment.id).delete_all
    photo_ids = repo.photos.pluck(:id)
    attachments = ActiveStorage::Attachment.where(record_type: "Photo", record_id: photo_ids)
    blob_ids = attachments.pluck(:blob_id)
    attachments.delete_all
    ActiveStorage::Blob.where(id: blob_ids).delete_all
    repo.destroy
    User.unscoped.where(id: [owner.id, fan.id]).delete_all
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

  # The first call holds its transaction open after the change; the second must wait for it.
  def race
    paused = Queue.new
    resume = Queue.new
    first = in_thread do
      ActiveRecord::Base.transaction do
        result = yield
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        result
      end
    end
    ThreadPause.await(paused)
    second = in_thread { yield }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Thread.pass while blocked_backends.zero? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    resume << true
    [first.value, second.value]
  end

  it "takes a like back once" do
    Like.give(repo, fan)

    results = race { Like.take_back(repo, fan) }

    expect(results).to eq([true, false])
    expect([Like.where(repository_id: repo.id).count, repo.reload.like]).to eq([0, 0])
  end

  it "removes a vote once" do
    Upvote.cast(fan, comment, false)

    results = race { Upvote.retract(fan, comment, false) }

    expect(results).to eq([true, false])
    expect([Upvote.where(comment_id: comment.id).count, comment.reload.upvote]).to eq([0, 0])
  end

  it "switches a vote once" do
    Upvote.cast(fan, comment, false)

    results = race { Upvote.switch(fan, comment, true) }

    expect(results).to eq([true, false])
    expect(comment.reload.upvote).to eq(-1)
  end

  it "does not remove a vote that was switched meanwhile" do
    Upvote.cast(fan, comment, false)
    Upvote.switch(fan, comment, true)

    expect(Upvote.retract(fan, comment, false)).to be(false)
    expect(Upvote.where(comment_id: comment.id).count).to eq(1)
  end
end
