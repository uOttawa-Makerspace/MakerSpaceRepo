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

  describe "#active date and flag rules" do
    let(:admin) { create(:user, :admin) }

    def ann(**attrs)
      create(:announcement, :all, { user: admin }.merge(attrs))
    end

    it "includes announcements with no end date, today, or the future" do
      open_ended = ann(end_date: nil)
      today = ann(end_date: Time.zone.today)
      future = ann(end_date: Time.zone.today + 5)
      expect(Announcement.active).to include(open_ended, today, future)
    end

    it "excludes past end dates and inactive ones" do
      expired = ann(end_date: Time.zone.yesterday)
      inactive = ann(active: false)
      expect(Announcement.active).not_to include(expired, inactive)
    end

    it "does not filter by audience" do
      goals = %w[all admin staff volunteer regular_user nonsense]
      goals.each { |g| create(:announcement, user: admin, public_goal: g) }
      expect(Announcement.active.pluck(:public_goal)).to match_array(goals)
    end

    it "has a regular_user scope" do
      create(:announcement, :regular_user, user: admin)
      expect(Announcement.regular_user.count).to eq(1)
    end
  end

  describe "associations" do
    it "requires a user" do
      expect(Announcement.new(description: "x")).not_to be_valid
    end

    it "destroys dismissals with it" do
      admin = create(:user, :admin)
      a = create(:announcement, :all, user: admin)
      AnnouncementDismiss.create!(user: admin, announcement: a)
      expect { a.destroy }.to change(AnnouncementDismiss, :count).by(-1)
    end

    it "does not validate description or public_goal" do
      expect(Announcement.new(user: create(:user, :admin))).to be_valid
    end
  end
end
