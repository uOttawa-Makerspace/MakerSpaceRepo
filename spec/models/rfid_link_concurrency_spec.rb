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
        resume.pop
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      Rfid.link_to_user!(card_number, first_user)
    end
    paused.pop
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
end
