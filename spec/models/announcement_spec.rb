require 'rails_helper'

RSpec.describe Announcement, type: :model do

  describe 'Scope testing' do

    before :each do
      create(:user, :admin_user)
    end

    context 'active' do

      it 'should return 3 active users' do
        create(:announcement, :all)
        create(:announcement, :all)
        create(:announcement, :all)
        create(:announcement, :all, active: false)
        expect(Announcement.active.count).to eq(3)
      end

      it 'should return only volunteer announcements' do
        create(:announcement, :volunteer)
        create(:announcement, :regular_user)
        create(:announcement, :volunteer)
        create(:announcement, :volunteer, active: false)
        create(:announcement, :all)
        expect(Announcement.volunteers.count).to eq(3)
      end

      it 'should return announcements for all' do
        create(:announcement, :volunteer)
        create(:announcement, :regular_user)
        create(:announcement, :volunteer)
        create(:announcement, :volunteer, active: false)
        create(:announcement, :all)
        expect(Announcement.all_users.count).to eq(1)
      end

      it 'should return announcements for admins' do
        create(:announcement, :volunteer)
        create(:announcement, :admin)
        create(:announcement, :volunteer)
        create(:announcement, :admin, active: false)
        create(:announcement, :all)
        expect(Announcement.admins.count).to eq(2)
      end

      it 'should return announcements for staff' do
        create(:announcement, :staff)
        create(:announcement, :admin)
        create(:announcement, :volunteer)
        create(:announcement, :staff, active: false)
        create(:announcement, :all)
        expect(Announcement.staff.count).to eq(2)
      end

    end

  end

end
