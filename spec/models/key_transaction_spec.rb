require "rails_helper"

RSpec.describe KeyTransaction, type: :model do
  describe "Associations" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:key).without_validating_presence }
    end
  end

  describe "Validations" do
    before :each do
      @user = create(:user, :regular_user)
      @space = create(:space)
      @key =
        create(:key, :regular_key_type, :inventory_status, space_id: @space.id)
    end

    context "open transaction validation" do
      it "refuses a second open transaction for the same key" do
        create(:key_transaction, key_id: @key.id, deposit_amount: 20, user_id: @user.id)
        second = build(:key_transaction, key_id: @key.id, deposit_amount: 20, user_id: @user.id)
        expect(second).not_to be_valid
        expect(second.errors[:key_id]).to include("already has an open transaction")
      end

      it "allows a new open transaction once the earlier one is returned" do
        create(:key_transaction, key_id: @key.id, deposit_amount: 20, user_id: @user.id, return_date: Date.current)
        expect(build(:key_transaction, key_id: @key.id, deposit_amount: 20, user_id: @user.id)).to be_valid
      end

      it "lets an open transaction be closed" do
        kt = create(:key_transaction, key_id: @key.id, deposit_amount: 20, user_id: @user.id)
        expect { kt.close! }.not_to raise_error
      end
    end

    context "user validation" do
      it "should be valid since user is present" do
        kt =
          build(
            :key_transaction,
            key_id: @key.id,
            deposit_amount: 20,
            user_id: @user.id
          )
        expect(kt.valid?).to be_truthy
      end

      it "should be invalid since user is not present" do
        kt = build(:key_transaction, key_id: @key.id, deposit_amount: 20)
        expect(kt.valid?).to be_falsey
      end
    end

    context "key validation" do
      it "should be valid since key is present" do
        kt =
          build(
            :key_transaction,
            deposit_amount: 20,
            user_id: @user.id,
            key_id: @key.id
          )
        expect(kt.valid?).to be_truthy
      end

      it "should be invalid since key is not present" do
        kt = build(:key_transaction, deposit_amount: 20, user_id: @user.id)
        expect(kt.valid?).to be_falsey
      end
    end

    context "deposit amount validation" do
      it "should be valid since deposit amount is present" do
        kt =
          build(
            :key_transaction,
            user_id: @user.id,
            key_id: @key.id,
            deposit_amount: 20
          )
        expect(kt.valid?).to be_truthy
      end

      it "should be invalid since deposit amount is not present" do
        kt =
          build(
            :key_transaction,
            user_id: @user.id,
            key_id: @key.id,
            deposit_amount: nil
          )
        expect(kt.valid?).to be_falsey
      end
    end
  end

  describe "Scopes" do
    before :each do
      @user = create(:user, :regular_user)
      @space = create(:space)
      @key =
        create(:key, :regular_key_type, :inventory_status, space_id: @space.id)
      create(:key_transaction, :returned, user_id: @user.id, key_id: @key.id)
      create(:key_transaction, user_id: @user.id, key_id: @key.id)
      create(
        :key_transaction,
          :returned,
          :deposit_returned,
          user_id: @user.id,
          key_id: @key.id
        )
    end

    context "#returned" do
      it "should return 2" do
        expect(KeyTransaction.returned.count).to eq(2)
      end
    end

    context "#not_returned" do
      it "should return 1" do
        expect(KeyTransaction.not_returned.count).to eq(1)
      end
    end

    context "#awaiting_deposit_return" do
      it "should return 1" do
        expect(KeyTransaction.awaiting_deposit_return.count).to eq(1)
      end
    end
  end
end
