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
      expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "accepts only the roles nil, blank and open_hours (makeroom was removed in chunk 20a)" do
      expect(described_class.new(space: space, calendar_url: "u", role: "x")).not_to be_valid
      expect(described_class.new(space: space, calendar_url: "u", role: "makeroom")).not_to be_valid
      [nil, "", "open_hours"].each do |role|
        expect(described_class.new(space: space, calendar_url: "u", role: role)).to be_valid
      end
    end
  end

  describe "color" do
    let(:space) { create(:space) }

    def calendar(color) = described_class.new(space: space, calendar_url: "u", color: color)

    it "accepts a #rrggbb value, a blank value and no value" do
      ["#3788d8", "", nil].each { |color| expect(calendar(color)).to be_valid }
    end

    it "normalizes case and surrounding whitespace" do
      expect(calendar(" #E6194B ").tap(&:validate).color).to eq("#e6194b")
    end

    it "rejects anything else" do
      ["red", "#fff", "#ggg000", "#e6194b;background:url(x)", "url(x)", "#e6194b\nx"].each do |color|
        expect(calendar(color)).not_to be_valid, "expected #{color.inspect} to be rejected"
      end
    end

    it "keeps an older row with a stored value editable until its colour changes" do
      old = described_class.create!(space: space, calendar_url: "u")
      old.update_columns(color: "teal")
      expect(old.reload.update(name: "Renamed")).to be(true)
      expect(old.update(color: "navy")).to be(false)
      expect(old.update(color: "#008080")).to be(true)
    end
  end
end

RSpec.describe StaffNeededCalendar, "on the admin calendar", type: :model do
  it "is named, or called Unnamed Calendar" do
    expect(described_class.new(name: "Hours").display_name).to eq("Hours")
    expect(described_class.new(name: "").display_name).to eq("Unnamed Calendar")
  end

  it "carries the id its imported rows have" do
    url = "https://calendar.example/open.ics"
    expect(described_class.new(calendar_url: url).feed_id).to eq(ImportedCalendar.new(url, "Hours", nil).id)
  end

  it "lists only the calendars with a link" do
    linked = described_class.create!(calendar_url: "https://calendar.example/a.ics")
    described_class.create!(calendar_url: "")

    expect(described_class.linked).to eq([linked])
  end
end
