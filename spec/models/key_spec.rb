require "rails_helper"

RSpec.describe Key, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:supervisor).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
      it { should belong_to(:key_request).without_validating_presence }
    end

    context "has_many" do
      it { should have_many(:key_transactions) }
    end
  end

  describe "Validations" do
    before :all do
      @space = create(:space)
      @user = create(:user, :regular_user)
      @kr =
        create(
          :key_request,
          :status_approved,
          :all_questions_answered,
          user_id: @user.id,
          supervisor_id: @user.id,
          space_id: @space.id
        )
    end

    context "user validation" do
      it "should be valid because user is present" do
        key =
          build(
            :key,
            :held_status,
            space_id: @space.id,
            user_id: @user.id,
            supervisor_id: @user.id,
            key_request_id: @kr.id
          )
        expect(key.valid?).to be_truthy
      end

      it "should be valid because it is not held" do
        key = build(:key, :inventory_status, space_id: @space.id)
        expect(key.valid?).to be_truthy
      end

      it "should not be valid since it is held" do
        key = build(:key, :held_status, space_id: @space.id)
        expect(key.valid?).to be_falsey
      end
    end

    context "space validation" do
      it "should be valid because space is present" do
        key =
          build(:key, :inventory_status, :regular_key_type, space_id: @space.id)
        expect(key.valid?).to be_truthy
      end

      it "should be valid because it's a keycard" do
        key = build(:key, :inventory_status, :keycard_key_type)
        expect(key.valid?).to be_truthy
      end

      it "should not be valid because it's a regular key" do
        key = build(:key, :inventory_status, :regular_key_type)
        expect(key.valid?).to be_falsey
      end
    end
  end

  describe "Methods" do
    before :all do
      @space = create(:space)
      @user = create(:user, :admin)
      @key =
        create(:key, :inventory_status, :regular_key_type, space_id: @space.id)
      @key_request =
        create(
          :key_request,
          :status_approved,
          :all_questions_answered,
          space_id: @space.id,
          user_id: @user.id,
          supervisor_id: @user.id
        )
    end

    context "#get_latest_key_transaction" do
      it "should get the latest key transaction" do
        create(:key_transaction, key_id: @key.id, user_id: @user.id)
        kt2 = create(:key_transaction, key_id: @key.id, user_id: @user.id)

        expect(@key.get_latest_key_transaction).to eq(kt2)
      end
    end

    context "#get_all_key_transactions" do
      it "should get all key transactions from the specified key" do
        create(:key_transaction, key_id: @key.id, user_id: @user.id)
        create(:key_transaction, key_id: @key.id, user_id: @user.id)

        expect(@key.get_all_key_transactions.length).to eq(2)
      end

      it "should return nothing" do
        create(:key_transaction, key_id: @key.id, user_id: @user.id)
        create(:key_transaction, key_id: @key.id, user_id: @user.id)
        otherKey =
          create(
            :key,
            :inventory_status,
            :regular_key_type,
            space_id: @space.id
          )

        expect(otherKey.get_all_key_transactions).to eq([])
      end
    end

    context "#get_keycode" do
      it "should return the space's keycode" do
        expect(@key.get_keycode).to eq(@key.space.keycode)
      end

      it "should return the key's custom keycode" do
        key =
          create(
            :key,
            :inventory_status,
            :keycard_key_type,
            space_id: @space.id
          )
        expect(key.get_keycode).to eq(key.custom_keycode)
      end
    end
  end
end
