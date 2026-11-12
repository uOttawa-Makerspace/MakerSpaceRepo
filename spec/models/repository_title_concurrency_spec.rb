# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving. One owner creates two repositories with the same title at
# the same moment. The first inserts its row and parks before committing; the second passes the title validation
# (it cannot see the uncommitted row), so its insert waits on the unique index. Once the first commits, the second
# must report the same error as a failed validation instead of raising.
RSpec.describe Repository, "title uniqueness under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:owner) { create(:user) }
  let!(:last_blob_id) { ActiveStorage::Blob.maximum(:id) || 0 }

  after do
    Repository.unscoped.where(user_id: owner.id).find_each(&:destroy)
    Repository.unscoped.where(user_id: owner.id).delete_all
    User.unscoped.where(id: owner.id).destroy_all
    ActiveStorage::Attachment.where("blob_id > ?", last_blob_id).delete_all
    ActiveStorage::Blob.where("id > ?", last_blob_id).delete_all
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

  it "stores the title once and gives the loser the title error" do
    parked = Queue.new
    resume = Queue.new
    one = in_thread do
      Repository.transaction do
        create(:repository, owner: owner, title: "Racing Title")
        parked << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
    end
    ThreadPause.await(parked)
    loser = build(:repository, owner: owner, title: "Racing Title")
    two = in_thread { [loser.save, loser.errors.full_messages] }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    expect(one.value).not_to be_a(StandardError)
    saved, messages = two.value
    expect(saved).to be(false)
    expect(messages).to eq(["Title Project title is already in use."])
    expect(Repository.unscoped.where(user_id: owner.id, title: "Racing Title").count).to eq(1)
  end

  it "leaves an enclosing transaction usable after losing the race" do
    create(:repository, owner: owner, title: "Taken Title")
    loser = build(:repository, owner: owner, title: "Taken Title")
    allow(loser).to receive(:valid?).and_return(true)

    Repository.transaction do
      expect(loser.save(validate: false)).to be(false)
      expect(loser.errors[:title]).to eq(["Project title is already in use."])
      expect(Repository.unscoped.where(user_id: owner.id).count).to eq(1)
    end
  end
end
