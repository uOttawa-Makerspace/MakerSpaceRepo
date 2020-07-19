require 'rails_helper'

RSpec.describe VolunteerTaskRequest, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:volunteer_task) }
    end

  end

  describe "#scopes" do

    before(:all) do
      create(:volunteer_task_request, :approved)
      create(:volunteer_task_request, :approved)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :rejected)
      create(:volunteer_task_request, :not_processed)
    end

    context "approved" do

      it 'should get the approved hours' do
        expect(VolunteerTaskRequest.approved.count).to eq(2)
      end

    end

    context "rejected" do

      it 'should get the rejected hours' do
        expect(VolunteerTaskRequest.rejected.count).to eq(3)
      end

    end

    context "not_processed" do

      it 'should get the not_processed hours' do
        expect(VolunteerTaskRequest.not_processed.count).to eq(1)
      end

    end

    context "processed" do

      it 'should get the processed hours' do
        expect(VolunteerTaskRequest.processed.count).to eq(5)
      end

    end

  end

  describe "model methods" do

    context "#status" do

      it 'should be approved' do
        create(:volunteer_task_request, :approved)
        expect(VolunteerTaskRequest.last.status).to eq("Approved")
      end

      it 'should be not approved' do
        create(:volunteer_task_request, :rejected)
        expect(VolunteerTaskRequest.last.status).to eq("Not Approved")
      end

      it 'should be not accessed' do
        create(:volunteer_task_request, :not_processed)
        expect(VolunteerTaskRequest.last.status).to eq("Not accessed")
      end

    end

    context "#volunteer_task_join" do

      it 'should create volunteer hour' do
        create(:volunteer_task_request)
        create(:volunteer_task_join, :active, volunteer_task_id: VolunteerTaskRequest.last.volunteer_task.id, user_id: VolunteerTaskRequest.last.user_id)
        expect(VolunteerTaskRequest.last.volunteer_task_join.user_id).to eq(User.last.id)
        expect(VolunteerTaskRequest.last.volunteer_task_join.volunteer_task_id).to eq(VolunteerTaskRequest.last.volunteer_task.id)
      end

    end

  end

end
