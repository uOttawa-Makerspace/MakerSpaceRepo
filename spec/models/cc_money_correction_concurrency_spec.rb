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

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  # Runs the correction on a second connection while this one holds the row lock, and lets it go on once it waits.
  def correct_while_locked(&locked_block)
    thread = nil
    CcMoney.transaction do
      row.lock!
      thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          CcMoney.find(row.id).correct_purchase_email!("right@example.com", by: admin)
        end
      end
      Timeout.timeout(10) { sleep 0.05 until blocked_backends.positive? }
      locked_block.call
    end
    thread.value
  end

  it "refuses to correct a row that was claimed first" do
    outcome = correct_while_locked { row.update!(user: buyer, linked: true) }
    expect(outcome).to eq(:already_linked)
    expect(row.reload).to have_attributes(linked: true, purchaser_email: buyer.email, claim_token_generation: 0)
    expect(CcMoneyEmailCorrection.where(cc_money_id: row.id)).to be_empty
  end

  it "leaves a claim that waited on the correction refused as superseded" do
    stale = CcMoney.for_claim_token(row.claim_token)
    outcome = correct_while_locked { nil }
    expect(outcome).to eq(:corrected)
    expect(stale.link_to(buyer)).to eq(:superseded)
    expect(row.reload).to have_attributes(linked: false, purchaser_email: "right@example.com", claim_token_generation: 1)
  end
end
