require 'rails_helper'

RSpec.describe VolunteerHour, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:volunteer_task) }
    end

  end

  describe "#scopes" do

    before(:all) do
      create(:volunteer_hour, :approved1)
      create(:volunteer_hour, :approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_processed)
    end

    context "approved" do

      it 'should get the approved hours' do
        expect(VolunteerHour.approved.count).to eq(2)
      end

    end

    context "rejected" do

      it 'should get the rejected hours' do
        expect(VolunteerHour.rejected.count).to eq(3)
      end

    end

    context "not_processed" do

      it 'should get the not_processed hours' do
        expect(VolunteerHour.not_processed.count).to eq(1)
      end

    end

    context "processed" do

      it 'should get the processed hours' do
        expect(VolunteerHour.processed.count).to eq(5)
      end

    end

  end

  describe "model methods" do

    context "#was_approved?" do

      it 'should be processed' do
        create(:volunteer_hour, :not_approved1)
        expect(VolunteerHour.last.was_processed?).to be_truthy
      end

      it 'should not be processed' do
        create(:volunteer_hour, :not_processed)
        expect(VolunteerHour.last.was_processed?).to be_falsey
      end

    end

    context "#create_volunteer_hour_from_approval" do

      it 'should create volunteer hour' do
        user = create(:user, :volunteer_with_volunteer_program)
        task = create(:volunteer_task)
        expect{ VolunteerHour.create_volunteer_hour_from_approval(user.id, task.id, task.hours) }.to change(VolunteerHour, :count).by(1)
      end
      
    end

  end

end
