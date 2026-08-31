require "rails_helper"

RSpec.describe Announcement, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Scopes" do
    let(:admin) { create(:user, :admin) }

    before :each do
      create(:announcement, :all, user: admin)
      create(:announcement, :all, user: admin)
      create(:announcement, :all, active: false, user: admin)
      create(:announcement, :volunteer, user: admin)
      create(:announcement, :volunteer, user: admin)
      create(:announcement, :volunteer, user: admin)
      create(:announcement, :volunteer, active: false, user: admin)
      create(:announcement, :volunteer, active: false, user: admin)
      create(:announcement, :regular_user, user: admin)
      create(:announcement, :regular_user, user: admin)
      create(:announcement, :regular_user, active: false, user: admin)
      create(:announcement, :regular_user, active: false, user: admin)
      create(:announcement, :regular_user, active: false, user: admin)
      create(:announcement, :admin, user: admin)
      create(:announcement, :admin, user: admin)
      create(:announcement, :admin, active: false, user: admin)
      create(:announcement, :admin, active: false, user: admin)
      create(:announcement, :staff, user: admin)
      create(:announcement, :staff, active: false, user: admin)
    end

    context "#active" do
      it "should return active announcements" do
        expect(Announcement.active.count).to eq(10)
      end
    end

    context "#volunteers" do
      it "should return announcements for volunteers" do
        expect(Announcement.volunteers.count).to eq(5)
      end
    end

    context "#all_users" do
      it "should return announcements for all" do
        expect(Announcement.all_users.count).to eq(3)
      end
    end

    context "#admins" do
      it "should return announcements for admins" do
        expect(Announcement.admins.count).to eq(4)
      end
    end

    context "#staff" do
      it "should return announcements for staff" do
        expect(Announcement.staff.count).to eq(2)
      end
    end
  end
end
