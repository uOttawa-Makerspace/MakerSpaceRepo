require "rails_helper"

RSpec.describe DesignDay, type: :model do
  describe "#semester" do
    {
      Date.new(2026, 1, 1) => :winter,
      Date.new(2026, 2, 15) => :winter,
      Date.new(2026, 4, 30) => :winter,
      Date.new(2026, 5, 1) => :summer,
      Date.new(2026, 6, 15) => :summer,
      Date.new(2026, 8, 31) => :summer,
      Date.new(2026, 9, 1) => :fall,
      Date.new(2026, 10, 15) => :fall,
      Date.new(2026, 12, 31) => :fall
    }.each do |day, semester|
      it "is #{semester} on #{day}" do
        expect(build(:design_day, day: day).semester).to eq(semester)
      end
    end
  end

  describe "#year" do
    it "is the year of the day" do
      expect(build(:design_day, day: Date.new(2025, 10, 3)).year).to eq(2025)
    end
  end

  describe "#can_be_published?" do
    it "is true when live with a sheet key" do
      expect(build(:design_day, is_live: true, sheet_key: "abc")).to be_can_be_published
    end

    it "is false when not live" do
      expect(build(:design_day, is_live: false, sheet_key: "abc")).not_to be_can_be_published
    end

    it "is false without a sheet key" do
      expect(build(:design_day, is_live: true, sheet_key: "")).not_to be_can_be_published
    end
  end

  describe "floorplans" do
    it "lists urls and titles of attached floorplans" do
      ActiveStorage::Current.url_options = { host: "example.test" }
      design_day = build(:design_day)
      design_day.floorplans.first.blob.metadata[:floorplan_title] = "Level 1"
      expect(design_day.floorplan_urls.length).to eq(1)
      expect(design_day.floorplan_urls.first).to be_a(String)
      expect(design_day.floorplan_titles).to eq(["Level 1"])
    end

    it "answers nil without attachments" do
      design_day = DesignDay.new(day: Date.new(2026, 3, 14))
      expect(design_day.floorplan_urls).to be_nil
      expect(design_day.floorplan_titles).to be_nil
    end
  end

  describe ".instance" do
    it "creates a design day for today when none exists" do
      expect { DesignDay.instance }.to change(DesignDay.unscoped, :count).by(1)
      expect(DesignDay.instance.day).to eq(Time.zone.today)
    end

    it "returns the latest existing one" do
      create(:design_day, day: Date.new(2025, 3, 1))
      latest = create(:design_day, day: Date.new(2026, 3, 1))
      expect(DesignDay.instance).to eq(latest)
    end
  end
end
