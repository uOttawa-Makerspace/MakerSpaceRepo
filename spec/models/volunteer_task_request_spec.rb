# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteerTaskRequest, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
    end
  end

  describe "#scopes" do
    before(:each) do
      create(:volunteer_task_request, :approved)
      create(:volunteer_task_request, :approved)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :not_processed)
    end

    context "approved" do
      it "should get the approved hours" do
        expect(VolunteerTaskRequest.approved.count).to eq(2)
      end
    end

    context "rejected" do
      it "should get the rejected hours" do
        expect(VolunteerTaskRequest.rejected.count).to eq(3)
      end
    end

    context "not_processed" do
      it "should get the not_processed hours" do
        expect(VolunteerTaskRequest.not_processed.count).to eq(1)
      end
    end

    context "processed" do
      it "should get the processed hours" do
        expect(VolunteerTaskRequest.processed.count).to eq(5)
      end
    end
  end

  describe "model methods" do
    context "#status" do
      it "should be approved" do
        create(:volunteer_task_request, :approved)
        expect(VolunteerTaskRequest.last.status).to eq("Approved")
      end

      it "should be not approved" do
        create(:volunteer_task_request, :rejected)
        expect(VolunteerTaskRequest.last.status).to eq("Not Approved")
      end

      it "should be not accessed" do
        create(:volunteer_task_request, :not_processed)
        expect(VolunteerTaskRequest.last.status).to eq("Not accessed")
      end
    end

    context "#volunteer_task_join" do
      it "should create volunteer hour" do
        task_request = create(:volunteer_task_request)
        create(
          :volunteer_task_join,
          :active,
          volunteer_task_id: task_request.volunteer_task.id,
          user_id: task_request.user_id
        )
        expect(task_request.reload.volunteer_task_join.user_id).to eq(task_request.user_id)
        expect(task_request.volunteer_task_join.volunteer_task_id).to eq(task_request.volunteer_task_id)
      end
    end
  end
end

# Chunk 13 characterization.
RSpec.describe VolunteerTaskRequest, "status, join lookup and search", type: :model do
  it "#status maps approval to labels" do
    expect(build(:volunteer_task_request, :approved).status).to eq("Approved")
    expect(build(:volunteer_task_request, :rejected).status).to eq("Not Approved")
    expect(build(:volunteer_task_request, :not_processed).status).to eq("Not accessed")
  end

  it "allows duplicates for the same user and task" do
    req = create(:volunteer_task_request, :not_processed)
    expect { create(:volunteer_task_request, user: req.user, volunteer_task: req.volunteer_task) }
      .to change(VolunteerTaskRequest, :count).by(1)
  end

  describe "#volunteer_task_join" do
    let(:req) { create(:volunteer_task_request) }

    it "returns the LAST active join of the requester on the task" do
      create(:volunteer_task_join, volunteer_task: req.volunteer_task, user: req.user, active: true)
      newest = create(:volunteer_task_join, volunteer_task: req.volunteer_task, user: req.user, active: true)
      create(:volunteer_task_join, volunteer_task: req.volunteer_task, user: req.user, active: false)
      expect(req.volunteer_task_join).to eq(newest)
    end

    it "is nil without an active join, or without a task" do
      expect(req.volunteer_task_join).to be_nil
      expect(VolunteerTaskRequest.new.volunteer_task_join).to be_nil
    end
  end

  describe ".filter_by_attribute" do
    let!(:space) { create(:space, name: "Lab Alpha") }
    let!(:user) { create(:user, :volunteer_with_volunteer_program, name: "Ada Lovelace", username: "adal") }
    let!(:task) { create(:volunteer_task, title: "Laser Night", space: space) }
    let!(:hit) { create(:volunteer_task_request, user: user, volunteer_task: task) }
    let!(:miss) { create(:volunteer_task_request) }

    it "returns everything for blank input" do
      expect(described_class.filter_by_attribute(nil)).to include(hit, miss)
      expect(described_class.filter_by_attribute("   ")).to include(hit, miss)
    end

    it "matches user name, username, task title and space name case-insensitively" do
      %w[LOVELACE adal laser ALPHA].each do |term|
        expect(described_class.filter_by_attribute(term)).to eq([hit])
      end
    end

    it "strips a raw 'search_pending=' prefix and turns '+' into spaces" do
      expect(described_class.filter_by_attribute("search_pending=ada+lovelace")).to eq([hit])
      expect(described_class.filter_by_attribute("search_processed=laser night")).to eq([hit])
    end

    it "treats an input that is only a prefix as blank" do
      expect(described_class.filter_by_attribute("search_pending=")).to include(hit, miss)
    end
  end
end
