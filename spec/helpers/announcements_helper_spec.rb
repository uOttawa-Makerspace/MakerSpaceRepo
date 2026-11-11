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
