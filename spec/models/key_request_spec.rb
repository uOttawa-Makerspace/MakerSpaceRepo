require "rails_helper"

RSpec.describe KeyRequest, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:supervisor).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "Validations" do
    before :all do
      @user = create(:user, :regular_user)
      @space = create(:space)
    end

    context "user validation" do
      it "should be valid since user is present" do
        kr =
          build(
            :key_request,
            :status_in_progress,
            space_id: @space.id,
            supervisor_id: @user.id,
            user_id: @user.id
          )
        expect(kr.valid?).to be_truthy
      end

      it "should be invalid since user is not present" do
        kr =
          build(
            :key_request,
            :status_in_progress,
            space_id: @space.id,
            supervisor_id: @user.id
          )
        expect(kr.valid?).to be_falsey
      end
    end

    context "space validation" do
      it "should be valid since space is present" do
        kr =
          build(
            :key_request,
            :status_in_progress,
            user_id: @user.id,
            supervisor_id: @user.id,
            space_id: @space.id
          )
        expect(kr.valid?).to be_truthy
      end

      it "should be invalid since space is not present" do
        kr =
          build(
            :key_request,
            :status_in_progress,
            user_id: @user.id,
            supervisor_id: @user.id
          )
        expect(kr.valid?).to be_falsey
      end
    end

    context "question and form validations" do
      it "should be valid since all form contents are filled" do
        kr =
          build(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @user.id,
            supervisor_id: @user.id,
            space_id: @space.id
          )
        expect(kr.valid?).to be_truthy
      end

      it "should be invalid since questions aren't answered" do
        kr =
          build(
            :key_request,
            :status_waiting_for_approval,
            user_id: @user.id,
            supervisor_id: @user.id,
            space_id: @space.id
          )
        expect(kr.valid?).to be_falsey
      end

      it "should be invalid since user did not read agreement" do
        kr =
          build(
            :key_request,
            :status_waiting_for_approval,
            :all_questions_answered,
            user_id: @user.id,
            supervisor_id: @user.id,
            space_id: @space.id,
            read_agreement: false
          )
        expect(kr.valid?).to be_falsey
      end
    end
  end
end
