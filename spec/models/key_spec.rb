require "rails_helper"

RSpec.describe Key, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:supervisor).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end

    context "has_many" do
      it { should have_many(:key_transactions) }
    end
  end

  describe "Validations" do
    before :each do
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
            supervisor_id: @user.id
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
    before :each do
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

  describe "assign and revoke" do
    let(:space) { create(:space) }
    let(:holder) { create(:user, :staff) }
    let(:supervisor) { create(:user, :admin) }
    let(:key) { create(:key, :regular_key_type, :inventory_status, space: space, number: 7) }
    let(:attrs) { { supervisor_id: supervisor.id } }

    it "assign_to! holds the key and records the transaction together" do
      expect { key.assign_to!(holder, attrs, 20) }.to change(KeyTransaction, :count).by(1)
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id, supervisor_id: supervisor.id)
      expect(key.key_transactions.last).to have_attributes(user_id: holder.id, deposit_amount: 20, return_date: nil)
    end

    it "assign_to! changes nothing when the transaction is invalid" do
      expect { key.assign_to!(holder, attrs, nil) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(key.reload).to have_attributes(status: "inventory", user_id: nil, supervisor_id: nil)
      expect(KeyTransaction.count).to eq(0)
    end

    it "assign_to! refuses a key that is not in inventory" do
      key.update!(status: :lost)
      expect { key.assign_to!(holder, attrs, 20) }.to raise_error(Key::StateError)
      expect(KeyTransaction.count).to eq(0)
    end

    it "revoke! returns the key and closes the open transaction together" do
      key.assign_to!(holder, attrs, 0)
      key.revoke!
      expect(key.reload).to have_attributes(status: "inventory", user_id: nil)
      expect(key.key_transactions.last).to have_attributes(return_date: Date.today, deposit_return_date: Time.zone.today)
    end

    it "revoke! refuses a held key with no open transaction and changes nothing" do
      key.update!(status: :held, user: holder, supervisor: supervisor)
      expect { key.revoke! }.to raise_error(Key::StateError, /no open transaction/)
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id)
    end

    it "revoke! refuses a key that is not held" do
      expect { key.revoke! }.to raise_error(Key::StateError, /Only a held key/)
    end

    it "revoke! rolls the key back when closing the transaction fails" do
      key.assign_to!(holder, attrs, 0)
      allow_any_instance_of(KeyTransaction).to receive(:close!).and_raise(ActiveRecord::RecordInvalid)
      expect { key.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(key.reload).to have_attributes(status: "held", user_id: holder.id)
    end
  end
end
