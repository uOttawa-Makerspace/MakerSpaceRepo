# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnnouncementsHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#return_public" do
    {
      "volunteer" => "Volunteers",
      "staff" => "Staff",
      "regular_user" => "All Users",
      "admin" => "Admins",
      "all" => "All Visitors (Even not signed in)"
    }.each do |goal, label|
      it "labels #{goal} as #{label}" do
        expect(helper.return_public(goal)).to eq(label)
      end
    end

    it "covers every audience the model accepts" do
      expect(Announcement::PUBLIC_GOALS.map { |goal| helper.return_public(goal) }).to all(be_present)
    end

    it "returns nothing for an unknown audience" do
      expect(helper.return_public("nobody")).to be_nil
    end
  end

  describe "#visible_announcements" do
    let!(:by_goal) do
      Announcement::PUBLIC_GOALS.index_with { |goal| create(:announcement, public_goal: goal, description: "For #{goal}") }
    end

    def bar_for(user, signed_in: user.persisted?)
      allow(helper).to receive(:current_user).and_return(user)
      helper.define_singleton_method(:signed_in?) { signed_in }
      helper.visible_announcements.map { |group, id, text| [group, id, text] }
    end

    def rows(*pairs)
      pairs.map { |group, goal| [group, by_goal[goal].id, "For #{goal}"] }
    end

    it "gives an admin every group, in bar order" do
      expect(bar_for(create(:user, :admin))).to eq(
        rows([:admins, "admin"], [:staff, "staff"], [:all_users, "regular_user"], [:all_visitors, "all"],
             [:volunteers, "volunteer"])
      )
    end

    it "gives staff the staff, signed-in, visitor and volunteer groups" do
      expect(bar_for(create(:user, :staff))).to eq(
        rows([:staff, "staff"], [:all_users, "regular_user"], [:all_visitors, "all"], [:volunteers, "volunteer"])
      )
    end

    it "gives a member of the volunteer program the signed-in, visitor and volunteer groups" do
      expect(bar_for(create(:user, :volunteer_with_volunteer_program))).to eq(
        rows([:all_users, "regular_user"], [:all_visitors, "all"], [:volunteers, "volunteer"])
      )
    end

    it "gives a regular user the signed-in and visitor groups" do
      expect(bar_for(create(:user, :regular_user))).to eq(rows([:all_users, "regular_user"], [:all_visitors, "all"]))
    end

    it "gives a guest only the visitor group" do
      expect(bar_for(User.new)).to eq(rows([:all_visitors, "all"]))
    end

    it "leaves out what the user dismissed and what is inactive" do
      user = create(:user, :regular_user)
      AnnouncementDismiss.create!(user: user, announcement: by_goal["all"])
      create(:announcement, public_goal: "regular_user", active: false, description: "Old")
      expect(bar_for(user)).to eq(rows([:all_users, "regular_user"]))
    end
  end

  describe "#return_active" do
    around { |example| travel_to(Time.zone.local(2026, 6, 15, 12)) { example.run } }

    it "is Yes for an active announcement with no end date" do
      expect(helper.return_active(Announcement.new(active: true, end_date: nil))).to eq("Yes")
    end

    it "is Yes for an active announcement ending today" do
      expect(helper.return_active(Announcement.new(active: true, end_date: Date.current))).to eq("Yes")
    end

    it "is No for an inactive announcement" do
      expect(helper.return_active(Announcement.new(active: false, end_date: nil))).to eq("No")
    end

    it "says the publishing date is over once the end date has passed" do
      announcement = Announcement.new(active: true, end_date: Date.current - 1)
      expect(helper.return_active(announcement)).to eq("Yes but the publishing date is over.")
    end

    it "returns nothing when active is unset (the column is nullable)" do
      expect(helper.return_active(Announcement.new(active: nil, end_date: nil))).to be_nil
    end
  end

  describe "in French" do
    around { |example| I18n.with_locale(:fr) { travel_to(Time.zone.local(2026, 6, 15, 12)) { example.run } } }

    it "labels the audience in French" do
      expect(helper.return_public("regular_user")).to eq("Tous les utilisateurs")
    end

    it "gives the state in French" do
      expect(helper.return_active(Announcement.new(active: false, end_date: nil))).to eq("Non")
      expect(helper.return_active(Announcement.new(active: true, end_date: Date.current - 1))).to eq("Oui, mais la date de publication est passée.")
    end
  end

  describe "#return_active across the Toronto day boundary" do
    it "uses the Toronto date at the end of the day, when UTC is already tomorrow" do
      travel_to(Time.find_zone("America/Toronto").local(2026, 6, 15, 23, 30)) do
        ending_today = Announcement.new(active: true, end_date: Date.new(2026, 6, 15))
        expect(helper.return_active(ending_today)).to eq("Yes")
      end
    end

    it "is over the Toronto morning after the end date" do
      travel_to(Time.find_zone("America/Toronto").local(2026, 6, 16, 0, 30)) do
        ended = Announcement.new(active: true, end_date: Date.new(2026, 6, 15))
        expect(helper.return_active(ended)).to eq("Yes but the publishing date is over.")
      end
    end
  end
end
