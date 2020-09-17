require 'rails_helper'

RSpec.describe Space, type: :model do

  describe 'Association' do

    context 'has_and_belongs_to_many' do
      it { should have_and_belong_to_many(:trainings) }
    end

    context 'has_many' do
      it { should have_many(:pi_readers) }
      it { should have_many(:lab_sessions) }
      it { should have_many(:users) }
      it { should have_many(:training_sessions) }
      it { should have_many(:certifications) }
      it { should have_many(:volunteer_requests) }
      it { should have_many(:volunteer_tasks) }
      it { should have_many(:popular_hours) }
    end
  end

  describe "validation" do

    context 'name' do

      it { should validate_presence_of(:name).with_message("A name is required for the space") }
      it { should validate_uniqueness_of(:name).with_message("Space already exists") }

    end

  end

  describe "methods" do

    context "#signed_in_users" do

      it 'should show the signed in users' do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(user_id: user.id, space_id: space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
        expect(Space.last.signed_in_users.first).to eq(User.find(user.id))
      end

    end

    context "#recently_signed_out_users" do

      it 'should get the recently signed out users' do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(user_id: user.id, space_id: space.id, sign_in_time: 1.day.ago, sign_out_time: 1.hour.ago)
        expect(Space.last.recently_signed_out_users.first).to eq(User.find(user.id))
      end

    end

  end

end
