require "rails_helper"

RSpec.describe CcMoney, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:order).without_validating_presence }
      it { should belong_to(:discount_code).without_validating_presence }
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

    context "#make_new_payment" do
      it "cc money should be created (with negative cc) after a payment" do
        user = create(:user, :regular_user)
        cc_money = CcMoney.make_new_payment(user, 13)
        expect(CcMoney.find(cc_money.id).cc).to eq(-13)
        expect(CcMoney.find(cc_money.id).user).to eq(user)
      end

      it "cc money should be created (with negative cc) after a payment" do
        user = create(:user, :regular_user)
        cc_money = CcMoney.make_new_payment(user, -17)
        expect(CcMoney.find(cc_money.id).cc).to eq(-17)
        expect(CcMoney.find(cc_money.id).user).to eq(user)
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

  describe ".make_new_payment" do
    it "stores a negative amount, refreshes the cached wallet and returns the row" do
      CcMoney.create!(user: user, cc: 100)
      payment = CcMoney.make_new_payment(user, 30)
      expect(payment.cc).to eq(-30)
      expect(user.reload.wallet).to eq(70)
    end

    it "keeps zero at zero and already-negative amounts unchanged" do
      expect(CcMoney.make_new_payment(user, 0).cc).to eq(0)
      expect(CcMoney.make_new_payment(user, -4).cc).to eq(-4)
    end

    it "lets the wallet go negative (no balance check at the model)" do
      CcMoney.make_new_payment(user, 25)
      expect(user.reload.wallet).to eq(-25)
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
