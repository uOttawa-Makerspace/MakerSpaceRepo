require "rails_helper"

RSpec.describe StaffNeededCalendar, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "characterization (chunk 14)" do
    let(:space) { create(:space) }

    it "requires a calendar_url at the database level" do
      expect { described_class.create!(space: space) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "allows only one open_hours calendar per space (validation, backed by a partial unique index)" do
      described_class.create!(space: space, calendar_url: "https://x.test/a.ics", role: "open_hours")
      second = described_class.new(space: space, calendar_url: "https://x.test/b.ics", role: "open_hours")
      expect(second).not_to be_valid
      expect(second.errors[:space_id]).to eq(["can only have one open_hours calendar"])
      expect(described_class.create!(space: create(:space), calendar_url: "https://x.test/c.ics", role: "open_hours")).to be_persisted
      expect(described_class.create!(space: space, calendar_url: "https://x.test/d.ics", role: "makeroom")).to be_persisted
      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "accepts only the roles nil, blank, open_hours and makeroom" do
      expect(described_class.new(space: space, calendar_url: "u", role: "x")).not_to be_valid
      [nil, "", "makeroom", "open_hours"].each do |role|
        expect(described_class.new(space: space, calendar_url: "u", role: role)).to be_valid
      end
    end
  end
end
