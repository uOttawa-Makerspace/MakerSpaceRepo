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
    before :each do
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

  describe "#submit" do
    let(:space) { create(:space) }
    let(:user) { create(:user, :staff) }
    let(:admin) { create(:user, :admin) }

    def request_in(status)
      create(:key_request, :all_questions_answered, user: user, supervisor: admin, space: space, status: status)
    end

    it "moves an in-progress request to waiting for approval" do
      kr = request_in(:in_progress)
      expect(kr.submit).to be_truthy
      expect(kr.reload.status).to eq("waiting_for_approval")
    end

    %i[waiting_for_approval approved].each do |status|
      it "leaves a #{status} request unchanged" do
        kr = request_in(status)
        expect(kr.submit).to be_falsey
        expect(kr.reload.status).to eq(status.to_s)
      end
    end

    it "moves a denied request back to waiting for approval and clears the reason" do
      kr = request_in(:denied)
      kr.update!(denial_reason: "Missing supervisor")
      expect(kr.submit).to be_truthy
      expect(kr.reload).to have_attributes(status: "waiting_for_approval", denial_reason: nil)
    end

    it "keeps the denial reason and the denied status when the resubmission is invalid" do
      kr = request_in(:denied)
      kr.update!(denial_reason: "Missing supervisor", question_3: nil)
      expect(kr.submit).to be_falsey
      expect(kr.reload).to have_attributes(status: "denied", denial_reason: "Missing supervisor")
    end

    it "leaves the reason of an in-progress request empty" do
      kr = request_in(:in_progress)
      expect(kr.submit).to be_truthy
      expect(kr.reload.denial_reason).to be_nil
    end
  end

  describe "status" do
    it "keeps the stored integer of each status, with denied appended" do
      expect(described_class.statuses).to eq(
        "in_progress" => 0, "waiting_for_approval" => 1, "approved" => 2, "denied" => 3
      )
    end
  end

  describe "#deny" do
    let(:kr) { create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: create(:user, :staff), supervisor: create(:user, :admin), space: create(:space)) }

    it "denies the request and stores the trimmed reason" do
      expect(kr.deny("  Not enough detail ")).to be_truthy
      expect(kr.reload).to have_attributes(status: "denied", denial_reason: "Not enough detail")
    end

    it "stores no reason when the reason is blank" do
      kr.deny("   ")
      expect(kr.reload).to have_attributes(status: "denied", denial_reason: nil)
    end

    it "refuses a reason longer than the limit and changes nothing" do
      expect(kr.deny("x" * (KeyRequest::MAX_DENIAL_REASON_LENGTH + 1))).to be_falsey
      expect(kr.reload).to have_attributes(status: "waiting_for_approval", denial_reason: nil)
    end
  end

  describe "#editable_by_owner?" do
    it "is true for in-progress and denied requests only" do
      editable = described_class.statuses.keys.select { |status| described_class.new(status: status).editable_by_owner? }
      expect(editable).to eq(%w[in_progress denied])
    end
  end
end
