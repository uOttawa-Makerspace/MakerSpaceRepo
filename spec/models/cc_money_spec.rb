require "rails_helper"

RSpec.describe CcMoney, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:order).without_validating_presence }
    end
  end

  describe "Methods" do
    context "#create_cc_money_from_approval" do
      it "cc money should be created if a volunteer task is approved" do
        volunteer = create(:user, :volunteer_with_volunteer_program)
        volunteer_task = create(:volunteer_task)
        cc_money =
          CcMoney.create_cc_money_from_approval(
            volunteer_task.id,
            volunteer.id,
            15
          )
        expect(CcMoney.find(cc_money.id).cc).to eq(15)
        expect(CcMoney.find(cc_money.id).user).to eq(volunteer)
        expect(CcMoney.find(cc_money.id).volunteer_task).to eq(volunteer_task)
      end
    end
  end
end

# ---- Chunk 8 characterization (shop) ---------------------------------------
RSpec.describe CcMoney, type: :model do
  let(:user) { create(:user, :regular_user) }

  it "defaults to linked: true; the unlinked/claimable flavor is created explicitly" do
    expect(CcMoney.create!(cc: 5, user: user).linked).to be(true)
    expect(CcMoney.create!(cc: 5, linked: false).linked).to be(false)
  end

  it "accepts rows with no user and no cc at all (no validations)" do
    expect { CcMoney.create! }.not_to raise_error
  end

  describe "#link_to" do
    let(:first_user) { create(:user, :regular_user) }
    let(:second_user) { create(:user, :regular_user) }

    it "gives an unlinked row to the user once and keeps that owner on a repeat or a second claim" do
      row = CcMoney.create!(cc: 10, linked: false)
      stale = CcMoney.find(row.id)
      expect(row.link_to(first_user)).to eq(:linked)
      expect(stale.link_to(second_user)).to eq(:already_linked)
      expect(stale.linked?).to be(true)
      expect(row.link_to(first_user)).to eq(:already_linked)
      expect(row.reload.user_id).to eq(first_user.id)
      expect(CcMoney.where(user_id: [first_user.id, second_user.id]).sum(:cc)).to eq(10)
    end
  end

  describe "claim tokens" do
    include ActiveSupport::Testing::TimeHelpers

    let(:buyer) { create(:user, :regular_user) }
    let(:row) { CcMoney.create!(cc: 10, linked: false, purchaser_email: buyer.email) }

    it "names the row, and stops working after the named lifetime" do
      expect(CcMoney::CLAIM_TOKEN_LIFETIME).to eq(30.days)
      token = row.claim_token
      expect(CcMoney.for_claim_token(token)).to eq(row)
      travel_to(30.days.from_now - 1.minute) { expect(CcMoney.for_claim_token(token)).to eq(row) }
      travel_to(30.days.from_now + 1.minute) { expect(CcMoney.for_claim_token(token)).to be_nil }
    end

    it "reads a token signed with the id alone as generation 0 and rejects garbage, other purposes and non-strings" do
      verifier = Rails.application.message_verifier(:cc)
      expect(CcMoney.for_claim_token(verifier.generate(row.id))).to eq(row)
      expect(CcMoney.for_claim_token(verifier.generate("not an id"))).to be_nil
      expect(CcMoney.for_claim_token(verifier.generate([row.id, 0], purpose: :other))).to be_nil
      expect([CcMoney.for_claim_token("garbage"), CcMoney.for_claim_token(nil), CcMoney.for_claim_token(1),
              CcMoney.for_claim_token(["x"])]).to all(be_nil)
    end

    it "raises RecordNotFound for a valid token whose row is gone" do
      token = row.claim_token
      CcMoney.where(id: row.id).delete_all
      expect { CcMoney.for_claim_token(token) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "#send_claim_email_to supersedes older tokens and keeps the stored address" do
      old = row.claim_token
      expect(row.send_claim_email_to("other@example.com")).to eq(:email_mismatch)
      expect(CcMoney.for_claim_token(old)).to eq(row)
      expect(row.send_claim_email_to(buyer.email.upcase)).to eq(:sent)
      expect(row.reload.claim_token_generation).to eq(1)
      expect(row.purchaser_email).to eq(buyer.email)
      expect(CcMoney.for_claim_token(old)).to be_nil
      expect(CcMoney.for_claim_token(row.claim_token)).to eq(row)
      expect(row.current_claim_generation?(0)).to be(false)
      expect(row.current_claim_generation?(1)).to be(true)
    end

    it "#send_claim_email_to records the address of a row that has none and refuses a bad address" do
      bare = CcMoney.create!(cc: 5, linked: false)
      expect(bare.send_claim_email_to("not-an-address")).to eq(:email_invalid)
      expect(bare.reload.purchaser_email).to be_nil
      expect(bare.send_claim_email_to(" Buyer@Example.com ")).to eq(:sent)
      expect(bare.reload.purchaser_email).to eq("buyer@example.com")
    end

    it "#send_claim_email_to refuses a row claimed meanwhile, even through a stale copy" do
      stale = CcMoney.find(row.id)
      row.link_to(buyer)
      expect(stale.send_claim_email_to(buyer.email)).to eq(:already_linked)
      expect(row.reload.claim_token_generation).to eq(0)
    end

    it "#claimable_by? is true for the unclaimed row's purchaser only, comparing normalised emails" do
      expect(row.claimable_by?(buyer)).to be(true)
      expect(row.claimable_by?(create(:user, :regular_user))).to be(false)
      expect(CcMoney.create!(cc: 1, linked: false).claimable_by?(buyer)).to be(false)
      expect(CcMoney.create!(cc: 1, linked: true, purchaser_email: buyer.email).claimable_by?(buyer)).to be(false)
    end

    it "#link_to refuses a copy loaded before a resend raised the generation" do
      copy = CcMoney.find(row.id)
      row.send_claim_email_to(buyer.email)
      expect(copy.link_to(buyer)).to eq(:superseded)
      expect(row.reload.linked).to be(false)
    end
  end

  describe ".debit! (the one wallet-debit operation)" do
    # A joinable caller transaction (the fixture transaction is not one).
    def in_caller_transaction(&block)
      ActiveRecord::Base.transaction(&block)
    end

    it "stores -amount, refreshes the cached wallet and returns the row" do
      CcMoney.create!(user: user, cc: 100)
      payment = in_caller_transaction { CcMoney.debit!(user, 30) }
      expect(payment.cc).to eq(-30)
      expect(user.reload.wallet).to eq(70)
    end

    it "writes a 0 row for 0 (free items) and passes order/proficient_project through" do
      order = Order.create!(user: user)
      row = in_caller_transaction { CcMoney.debit!(user, 0, order: order) }
      expect([row.cc, row.order_id, row.user_id]).to eq([0, order.id, user.id])
    end

    it "refuses an insufficient balance (no row; the caller's transaction rolls back)" do
      CcMoney.create!(user: user, cc: 20)
      expect do
        in_caller_transaction do
          Order.create!(user: user) # a caller write in the same transaction
          CcMoney.debit!(user, 25)
        end
      end.to raise_error(CcMoney::InsufficientBalance, "CC balance 20 does not cover 25")
      expect(user.cc_moneys.pluck(:cc)).to eq([20])
      expect(user.orders).to be_empty
    end

    it "refuses a negative amount" do
      expect { in_caller_transaction { CcMoney.debit!(user, -4) } }.to raise_error(CcMoney::InvalidAmount, /must not be negative/)
    end

    it "refuses to run outside a caller transaction" do
      CcMoney.create!(user: user, cc: 100)
      expect { CcMoney.debit!(user, 10) }
        .to raise_error(ArgumentError, "CcMoney.debit! must run inside the caller's transaction")
      expect { CcMoney.lock_wallet!(user) }
        .to raise_error(ArgumentError, "CcMoney.lock_wallet! must run inside the caller's transaction")
      expect(user.cc_moneys.pluck(:cc)).to eq([100])
    end

    def sql_during
      sqls = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| sqls << p[:sql] }
      yield
      sqls
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    def user_locks(sqls) = sqls.count { |q| q.include?('FROM "users"') && q.include?("FOR NO KEY UPDATE") }

    it "debit! after lock_wallet! (re-locking the row this transaction holds) and repeated debits all succeed" do
      CcMoney.create!(user: user, cc: 10)
      in_caller_transaction do
        locked = CcMoney.lock_wallet!(user)
        CcMoney.debit!(locked, 1)
        CcMoney.debit!(user, 2)
      end
      expect(user.cc_moneys.order(:id).pluck(:cc)).to eq([10, -1, -2])
      expect(user.reload.wallet).to eq(7)
    end

    it "debits inside a released requires_new block and after a rolled-back one hold the lock and stay correct" do
      CcMoney.create!(user: user, cc: 10)
      in_caller_transaction do
        ActiveRecord::Base.transaction(requires_new: true) { CcMoney.debit!(user, 1) }
        ActiveRecord::Base.transaction(requires_new: true) do
          CcMoney.debit!(user, 2)
          raise ActiveRecord::Rollback
        end
        CcMoney.debit!(user, 3)
      end
      expect(user.cc_moneys.order(:id).pluck(:cc)).to eq([10, -1, -3])
      expect(user.reload.wallet).to eq(6)
    end

    it "lock_wallet!/debit! inside a caller transaction leave its lock_timeout unchanged (no session setting)" do
      CcMoney.create!(user: user, cc: 10)
      in_caller_transaction do
        CcMoney.connection.execute("SET LOCAL lock_timeout = '7s'")
        CcMoney.debit!(user, 1)
        CcMoney.debit_all!(CcMoney.lock_wallet!(user), [[1, {}]])
        expect(CcMoney.connection.select_value("SELECT current_setting('lock_timeout')")).to eq("7s")
      end
    end

    it "debit_all! checks the TOTAL once, writes every row and refreshes the cached wallet once" do
      CcMoney.create!(user: user, cc: 30)
      sqls = sql_during do
        in_caller_transaction { CcMoney.debit_all!(user, [[10, {}], [15, {}]]) }
      end
      expect(user.cc_moneys.order(:id).pluck(:cc)).to eq([30, -10, -15])
      expect(user.reload.wallet).to eq(5)
      expect(sqls.count { |q| q.include?('SUM("cc_moneys"."cc")') }).to eq(1)
      expect(sqls.count { |q| q.start_with?('UPDATE "users"') }).to eq(1)
      expect(user_locks(sqls)).to eq(1)
    end

    it "debit_all! refuses to run outside a caller transaction" do
      CcMoney.create!(user: user, cc: 30)
      expect { CcMoney.debit_all!(user, [[1, {}]]) }
        .to raise_error(ArgumentError, "CcMoney.debit! must run inside the caller's transaction")
      expect(user.cc_moneys.pluck(:cc)).to eq([30])
    end

    it "debit_all! refuses when the total exceeds the balance even though each item fits" do
      CcMoney.create!(user: user, cc: 20)
      expect { in_caller_transaction { CcMoney.debit_all!(user, [[15, {}], [15, {}]]) } }
        .to raise_error(CcMoney::InsufficientBalance, "CC balance 20 does not cover 30")
      expect(user.cc_moneys.pluck(:cc)).to eq([20])
    end

    it "locks the user row (FOR NO KEY UPDATE) before writing" do
      sqls = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| sqls << p[:sql] }
      in_caller_transaction { CcMoney.debit!(user, 0) }
      ActiveSupport::Notifications.unsubscribe(sub)
      lock_at = sqls.index { |q| q.include?('FROM "users"') && q.include?("FOR NO KEY UPDATE") }
      insert_at = sqls.index { |q| q.start_with?('INSERT INTO "cc_moneys"') }
      expect(lock_at).to be < insert_at
    end
  end

  describe ".create_cc_money_from_approval" do
    it "is a plain positive credit linked to the task" do
      task = create(:volunteer_task)
      row = CcMoney.create_cc_money_from_approval(task.id, user.id, 8)
      expect([row.cc, row.user_id, row.volunteer_task_id, row.linked]).to eq([8, user.id, task.id, true])
    end
  end

  describe "wallet (User#update_wallet / #get_total_cc)" do
    it "caches the sum of all cc_moneys in users.wallet only when update_wallet is called" do
      user.update_column(:wallet, 0)
      CcMoney.create!(user: user, cc: 40)
      CcMoney.create!(user: user, cc: -15)
      expect(user.get_total_cc).to eq(25)
      expect(user.reload.wallet).to eq(0)
      user.update_wallet
      expect(user.reload.wallet).to eq(25)
    end

    it "refreshes the cache even for a user that fails validation (legacy data), and no-ops for a guest" do
      CcMoney.create!(user: user, cc: 40)
      user.update_column(:wallet, 0)
      user.update_column(:name, "") # now invalid (name presence)
      expect(user.reload).not_to be_valid
      user.update_wallet
      expect(user.reload.wallet).to eq(40)
      expect { User.new.update_wallet }.not_to raise_error
    end

    it "ignores the linked flag and other users' rows" do
      CcMoney.create!(user: user, cc: 10, linked: false)
      CcMoney.create!(user: create(:user, :regular_user), cc: 99)
      expect(user.get_total_cc).to eq(10)
    end

    it "destroying the user destroys their cc_moneys" do
      CcMoney.create!(user: user, cc: 10)
      expect { user.destroy }.to change(CcMoney, :count).by(-1)
    end
  end
end

RSpec.describe Order, ".checkout! transaction boundary", type: :model do
  let(:user) { create(:user, :regular_user) }

  it "refuses to run inside an already-open transaction (shared own_transaction rule)" do
    order = Order.create!(user: user)
    ActiveRecord::Base.transaction do
      expect { Order.checkout!(order, user) }.to raise_error(ArgumentError, "Order.checkout! must run as its own transaction")
    end
    expect(order.reload.order_status.name).to eq("In progress")
  end
end
