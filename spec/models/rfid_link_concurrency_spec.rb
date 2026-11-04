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
    allow(Rfid).to receive(:insert).and_wrap_original do |original, *args, **kwargs|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args, **kwargs)
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
    # unlink_card! must really be waiting for the owner's row, or the retry path is not exercised
    expect(blocked_backends).to be_positive
    release << true

    expect(holder.value).not_to be_a(StandardError)
    expect(unlinker.value).to eq(:unlinked)
    expect(Rfid.find_by!(card_number: card_number).user_id).to be_nil
  ensure
    User.unscoped.where(id: actor&.id).delete_all
  end

  # The owner changes between unlink_card!'s read of it and its locks on every attempt (the hook
  # moves the card to the other user right when unlink_card! takes the owner's row lock), so the
  # real retry loop runs to its cap. It must stop there and raise, leaving the card linked.
  it "unlink_card! gives up with OwnerChanging when the owner changes on every attempt" do
    Rfid.create!(card_number: card_number, user_id: first_user.id)
    actor = create(:user, :staff)
    others = { first_user.id => second_user.id, second_user.id => first_user.id }
    attempts = 0
    allow(User).to receive(:where).and_wrap_original do |original, *args, **kwargs, &block|
      if kwargs.key?(:id) && kwargs[:id].is_a?(Integer) && others.key?(kwargs[:id])
        attempts += 1
        Rfid.where(card_number: card_number).update_all(user_id: others.fetch(kwargs[:id]))
      end
      original.call(*args, **kwargs, &block)
    end

    expect { Rfid.unlink_card!(card_number, actor: actor) }.to raise_error(Rfid::OwnerChanging)
    expect(attempts).to eq(5)
    expect(Rfid.find_by!(card_number: card_number).user_id).to be_present
  ensure
    User.unscoped.where(id: actor&.id).delete_all
  end

  describe "creating a card row that another request creates at the same moment" do
    let(:space) { create(:space) }
    let(:reader_mac) { "aa:bb:cc:dd:ee:01" }

    after do
      TapBoxLog.where(card_number: card_number).delete_all
      Space.where(id: space.id).delete_all
    end

    # Pauses the first caller of Rfid.insert (just before its INSERT) until released.
    def pause_first_insert
      first = nil
      paused = Queue.new
      resume = Queue.new
      allow(Rfid).to receive(:insert).and_wrap_original do |original, *args, **kwargs|
        if Thread.current == first
          first = nil
          paused << true
          resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        end
        original.call(*args, **kwargs)
      end
      [->(thread) { first = thread }, paused, resume]
    end

    def tap_card
      RfidTap.call(card: card_number, space: space, mac_address: reader_mac)
    end

    it "two taps of one new card store one row; the first to insert reports the new card, the other a known unlinked card" do
      set_first, paused, resume = pause_first_insert
      one = in_thread do
        set_first.call(Thread.current)
        tap_card
      end
      ThreadPause.await(paused)
      second = tap_card
      resume << true

      first_result = one.value
      expect(first_result).not_to be_a(StandardError)
      expect(second.outcome).to eq(:new_card)
      expect(first_result.outcome).to eq(:unlinked_card)
      expect(Rfid.where(card_number: card_number).pluck(:user_id, :mac_address)).to eq([[nil, reader_mac]])
    end

    it "a tap racing a staff link of the same new card leaves one row, linked to the user" do
      set_first, paused, resume = pause_first_insert
      link = in_thread do
        set_first.call(Thread.current)
        Rfid.link_to_user!(card_number, first_user)
      end
      ThreadPause.await(paused)
      tapped = tap_card
      resume << true

      expect(link.value).to be_nil
      expect(tapped.outcome).to eq(:new_card)
      rows = Rfid.where(card_number: card_number)
      expect(rows.count).to eq(1)
      expect(rows.first.user_id).to eq(first_user.id)
      expect(rows.first.mac_address).to eq(reader_mac)
    end
  end

  # An admin assigning a card (the user's current card is unlinked, then the new one linked, in one
  # transaction) races a staff link of the same card to someone else. Both go through
  # link_to_user!, so one wins and the other is refused with the reason, and the loser's
  # transaction can be rolled back whole.
  it "an admin assign and a staff link of one card: exactly one wins, the other is refused" do
    actor = create(:user, :staff)
    Rfid.create!(card_number: card_number)
    old_card = Rfid.create!(card_number: "#{card_number}-OLD", user_id: second_user.id)
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(Rfid).to receive(:find_or_create_card).and_wrap_original do |original, *args, **kwargs|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      original.call(*args, **kwargs)
    end

    staff_link = in_thread do
      first = Thread.current
      Rfid.link_to_user!(card_number, first_user)
    end
    ThreadPause.await(paused)
    refusal = nil
    admin_assign = in_thread do
      Rfid.transaction do
        Rfid.unlink_from_user!(second_user, actor: actor)
        refusal = Rfid.link_to_user!(card_number, second_user)
        raise ActiveRecord::Rollback if refusal
      end
    end
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !admin_assign.alive? || Time.current > deadline
    expect(blocked_backends).to be_positive
    resume << true

    expect(staff_link.value).to be_nil
    expect(admin_assign.value).not_to be_a(StandardError)
    expect(refusal).to eq("is already linked to another user")
    expect(Rfid.where(card_number: card_number).pluck(:user_id)).to eq([first_user.id])
    expect(old_card.reload.user_id).to eq(second_user.id)
  ensure
    Rfid.where(card_number: ["#{card_number}-OLD"]).delete_all
    User.unscoped.where(id: actor&.id).delete_all
  end
end
