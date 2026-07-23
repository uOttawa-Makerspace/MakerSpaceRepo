require "rails_helper"

RSpec.describe Key, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:holder).without_validating_presence }
      it { should belong_to(:supervisor).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
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

    context "holder validation" do
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

      it "should be valid because external contact is present" do
        contact = create(:external_contact)
        key =
          build(
            :key,
            :held_status,
            space_id: @space.id,
            holder: contact,
            supervisor_id: @user.id
          )
        expect(key.valid?).to be_truthy
      end

      it "should be valid because it is not held" do
        key = build(:key, :inventory_status, space_id: @space.id)
        expect(key.valid?).to be_truthy
      end

      it "should not be valid since it is held with no holder" do
        key = build(:key, :held_status, space_id: @space.id)
        expect(key.valid?).to be_falsey
        expect(key.errors[:holder]).to include("A holder is required if the key is held")
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

    context "#key_request" do
      it "should return the key_request via the User holder" do
        @key.update!(holder: @user, status: :held, supervisor_id: @user.id)
        expect(@key.key_request).to eq(@key_request)
      end

      it "should return nil when the holder is an ExternalContact" do
        contact = create(:external_contact)
        @key.update!(holder: contact, status: :held, supervisor_id: @user.id)
        expect(@key.key_request).to be_nil
      end
    end

    context "#assignee_name and #assignee_email" do
      it "should return the User's name and email when held internally" do
        @key.update!(holder: @user, status: :held, supervisor_id: @user.id)
        expect(@key.assignee_name).to eq(@user.name)
        expect(@key.assignee_email).to eq(@user.email)
      end

      it "should return the ExternalContact's name and email when held externally" do
        contact = create(:external_contact, first_name: "Jane", last_name: "Doe")
        @key.update!(holder: contact, status: :held, supervisor_id: @user.id)
        expect(@key.assignee_name).to eq("Jane Doe")
        expect(@key.assignee_email).to eq(contact.email)
      end

      it "should return 'Unassigned' when there is no holder" do
        key = create(:key, :inventory_status, :regular_key_type, space_id: @space.id)
        expect(key.assignee_name).to eq("Unassigned")
        expect(key.assignee_email).to be_nil
      end
    end

    context "backward-compatibility shim" do
      it "exposes #user and #user_id only when the holder is a User" do
        @key.update!(holder: @user, status: :held, supervisor_id: @user.id)
        expect(@key.user).to eq(@user)
        expect(@key.user_id).to eq(@user.id)
      end

      it "returns nil from #user and #user_id when the holder is an ExternalContact" do
        contact = create(:external_contact)
        @key.update!(holder: contact, status: :held, supervisor_id: @user.id)
        expect(@key.user).to be_nil
        expect(@key.user_id).to be_nil
      end

      it "assigns the holder correctly via #user_id=" do
        key = create(:key, :inventory_status, :regular_key_type, space_id: @space.id)
        key.user_id = @user.id
        expect(key.holder).to eq(@user)
        expect(key.holder_type).to eq("User")
      end

      it "clears the holder via #user_id= when given nil" do
        @key.update!(holder: @user, status: :held, supervisor_id: @user.id)
        @key.user_id = nil
        expect(@key.holder).to be_nil
      end
    end
  end
end