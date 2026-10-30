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

    it "a Wallet from lock_wallet! in this transaction is not locked again; lock_wallet! bounds the lock waits" do
      CcMoney.create!(user: user, cc: 10)
      timeout = nil
      sqls = sql_during do
        in_caller_transaction do
          wallet = CcMoney.lock_wallet!(user)
          timeout = CcMoney.connection.select_value("SELECT current_setting('lock_timeout')")
          CcMoney.debit!(wallet, 1)
          CcMoney.debit!(wallet, 2)
        end
      end
      expect(user_locks(sqls)).to eq(1)
      expect(timeout).to eq("5s")
      expect(user.reload.wallet).to eq(7)
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
