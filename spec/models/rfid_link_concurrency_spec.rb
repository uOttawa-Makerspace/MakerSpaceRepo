# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see
# training_session_certify_concurrency_spec). rfids.card_number has no unique
# index, so Rfid.link_to_user! serialises on an advisory lock.
RSpec.describe Rfid, ".link_to_user! under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:first_user) { create(:user, :regular_user) }
  let!(:second_user) { create(:user, :regular_user) }
  let(:card_number) { "CONCURRENT0001" }

  after do
    Rfid.where(card_number: card_number).delete_all
    User.unscoped.where(id: [first_user.id, second_user.id]).delete_all
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

  # Thread 1 pauses after finding no card, just before creating it. Thread 2 then links the
  # same new number for another user: with the advisory lock it blocks until thread 1 commits
  # and then sees thread 1's card; without it, it creates its own and a duplicate row appears.
  it "two concurrent links of one new card number create exactly one row, owned by the first" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(Rfid).to receive(:insert_card).and_wrap_original do |original, *args|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      Rfid.link_to_user!(card_number, first_user)
    end
    ThreadPause.await(paused)
    two = in_thread { Rfid.link_to_user!(card_number, second_user) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    results = [one.value, two.value]
    expect(results.grep(StandardError)).to be_empty
    expect(results).to eq([nil, "is already linked to another user"])
    rows = Rfid.where(card_number: card_number)
    expect(rows.count).to eq(1)
    expect(rows.first.user_id).to eq(first_user.id)
  end

  # The owner of a card is only known by reading it, before the locks. Here a transaction holds the
  # owner's row, so unlink_card! has read the owner and waits for that lock; meanwhile the card is
  # moved to another user and committed. unlink_card! must notice and unlink the card from its new
  # owner, not report success for the old one.
  it "unlink_card! follows a card that was relinked to another user while it waited" do
    Rfid.create!(card_number: card_number, user_id: first_user.id)
    actor = create(:user, :staff)
    locked = Queue.new
    release = Queue.new
    holder = in_thread do
      Rfid.transaction do
        User.where(id: first_user.id).lock("FOR NO KEY UPDATE").take
        locked << true
        release.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        Rfid.where(card_number: card_number).update_all(user_id: second_user.id)
      end
    end
    ThreadPause.await(locked)
    unlinker = in_thread { Rfid.unlink_card!(card_number, actor: actor) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !unlinker.alive? || Time.current > deadline
    release << true

    expect(holder.value).not_to be_a(StandardError)
    expect(unlinker.value).to eq(:unlinked)
    expect(Rfid.find_by!(card_number: card_number).user_id).to be_nil
  ensure
    User.unscoped.where(id: actor&.id).delete_all
  end
end
