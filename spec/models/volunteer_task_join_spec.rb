require 'rails_helper'

RSpec.describe VolunteerTaskJoin, type: :model do

  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:volunteer_task) }
    end

  end

  describe "#scopes" do

    before(:all) do
      create(:volunteer_task_join, :active)
      create(:volunteer_task_join, :active)
      create(:volunteer_task_join, :not_active)
      create(:volunteer_task_join, :active_not_volunteer)
      create(:volunteer_task_join, :active_not_volunteer)
      create(:volunteer_task_join, :not_active_not_volunteer)
    end

    context "active" do

      it 'should get the active joins' do
        expect(VolunteerTaskJoin.active.count).to eq(4)
      end

    end

    context "not_active" do

      it 'should get the not active joins' do
        expect(VolunteerTaskJoin.not_active.count).to eq(2)
      end

    end

    context "user_type_volunteer" do

      it 'should get the user type volunteer' do
        expect(VolunteerTaskJoin.user_type_volunteer.count).to eq(3)
      end

    end

  end

end
