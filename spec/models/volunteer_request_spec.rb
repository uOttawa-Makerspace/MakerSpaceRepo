require 'rails_helper'

RSpec.describe VolunteerRequest, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:space) }
    end

  end

  describe "#scopes" do

    before(:all) do
      create(:volunteer_request, :approved)
      create(:volunteer_request, :approved)
      create(:volunteer_request, :rejected)
      create(:volunteer_request, :rejected)
      create(:volunteer_request, :rejected)
      create(:volunteer_request, :not_processed)
    end

    context "approved" do

      it 'should get the approved hours' do
        expect(VolunteerRequest.approved.count).to eq(2)
      end

    end

    context "rejected" do

      it 'should get the rejected hours' do
        expect(VolunteerRequest.rejected.count).to eq(3)
      end

    end

    context "not_processed" do

      it 'should get the not_processed hours' do
        expect(VolunteerRequest.not_processed.count).to eq(1)
      end

    end

    context "processed" do

      it 'should get the processed hours' do
        expect(VolunteerRequest.processed.count).to eq(5)
      end

    end

  end

end
