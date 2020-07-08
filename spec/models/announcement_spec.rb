require 'rails_helper'

RSpec.describe Announcement, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
    end
  end

  describe 'Scope testing' do
    before :all do
      create(:user, :admin_user)
      create(:announcement, :all)
      create(:announcement, :all)
      create(:announcement, :all, active: false)
      create(:announcement, :volunteer)
      create(:announcement, :volunteer)
      create(:announcement, :volunteer)
      create(:announcement, :volunteer, active: false)
      create(:announcement, :volunteer, active: false)
      create(:announcement, :regular_user)
      create(:announcement, :regular_user)
      create(:announcement, :regular_user, active: false)
      create(:announcement, :regular_user, active: false)
      create(:announcement, :regular_user, active: false)
      create(:announcement, :admin)
      create(:announcement, :admin)
      create(:announcement, :admin, active: false)
      create(:announcement, :admin, active: false)
      create(:announcement, :staff)
      create(:announcement, :staff, active: false)
    end

    context '#active' do
      it 'should return active announcements' do
        expect(Announcement.active.count).to eq(10)
      end
    end

    context '#volunteers' do
      it 'should return announcements for volunteers' do
        expect(Announcement.volunteers.count).to eq(5)
      end
    end

    context '#all_users' do
      it 'should return announcements for all' do
        expect(Announcement.all_users.count).to eq(3)
      end
    end

    context '#admins' do
      it 'should return announcements for admins' do
        expect(Announcement.admins.count).to eq(4)
      end
    end

    context '#staff' do
      it 'should return announcements for staff' do
        expect(Announcement.staff.count).to eq(2)
      end
    end
  end
end
