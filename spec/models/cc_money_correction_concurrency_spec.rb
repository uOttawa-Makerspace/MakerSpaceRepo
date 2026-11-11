# frozen_string_literal: true

require "rails_helper"

# A claim and a correction of the same unclaimed row race for its lock; whichever commits first wins and the
# other sees the result. Real second connection, like the wallet race specs.
RSpec.describe CcMoney, "correcting the purchase email while it is claimed", type: :model do
  self.use_transactional_tests = false

  let!(:admin) { create(:user, :admin) }
  let!(:buyer) { create(:user, :regular_user) }
  let!(:row) { CcMoney.create!(cc: 10, linked: false, purchaser_email: buyer.email) }

  after do
    CcMoneyEmailCorrection.where(cc_money_id: row.id).delete_all
    CcMoney.where(id: row.id).delete_all
    User.unscoped.where(id: [admin.id, buyer.id]).delete_all
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

  # The main thread gives up after ThreadPause::AWAIT_TIMEOUT; the holder is released by then (see `ensure`).
  def wait_until_blocked
    deadline = Time.current + ThreadPause::AWAIT_TIMEOUT
    until blocked_backends.positive?
      raise "the correction did not block on the row lock" if Time.current > deadline

      Thread.pass
    end
  end

  # Locks the row on its own connection, signals, parks until released, then does `work` and commits.
  def hold_row_lock(parked, release, &work)
    in_thread do
      CcMoney.transaction do
        CcMoney.find(row.id).lock!
        parked << true
        release.pop(timeout: ThreadPause::PARKED_TIMEOUT)
        work.call
      end
    end
  end

  def correct_in_thread = in_thread { CcMoney.find(row.id).correct_purchase_email("right@example.com", by: admin) }

  # A holder thread locks the row and parks; once it has signalled, the correction runs on another connection and
  # blocks on that lock; the holder then does `holder_work` and commits. Returns the correction's outcome.
  # Both threads are always released and joined, so a failure cannot leave a lock or an insert running into the
  # example's cleanup.
  def correct_while_locked(&holder_work)
    parked = Queue.new
    release = Queue.new
    holder = hold_row_lock(parked, release, &holder_work)
    contender = nil
    begin
      ThreadPause.await(parked, "the lock holder")
      contender = correct_in_thread
      wait_until_blocked
    ensure
      release << true
      [holder, contender].compact.each(&:join)
    end
    raise holder.value if holder.value.is_a?(StandardError)

    contender.value
  end

  it "refuses to correct a row that was claimed first" do
    outcome = correct_while_locked { CcMoney.find(row.id).update!(user: buyer, linked: true) }
    expect(outcome).to eq(:already_linked)
    expect(row.reload).to have_attributes(linked: true, purchaser_email: buyer.email, claim_token_generation: 0)
    expect(CcMoneyEmailCorrection.where(cc_money_id: row.id)).to be_empty
  end

  it "leaves a claim that waited on the correction refused as superseded" do
    stale = CcMoney.for_claim_token(row.claim_token)
    outcome = correct_while_locked { nil }
    expect(outcome).to eq(:corrected)
    expect(stale.link_to(buyer)).to eq(:superseded)
    expect(row.reload)
      .to have_attributes(linked: false, purchaser_email: "right@example.com", claim_token_generation: 1)
  end
end
