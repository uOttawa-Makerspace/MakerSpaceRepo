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

RSpec.describe StaffNeededCalendar, "on the opening-hours calendar", type: :model do
  let(:url) { "https://calendar.example/hours.ics" }
  let(:week) { CalendarWindow.new(RecurrenceRule::ZONE.local(2099, 1, 4), RecurrenceRule::ZONE.local(2099, 1, 11)) }
  let(:ics) do
    ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN", "BEGIN:VEVENT", "UID:open@ics.test", "DTSTAMP:20270101T000000Z",
     "DTSTART:20990105T150000Z", "DTEND:20990105T160000Z", "SUMMARY:Open", "END:VEVENT", "END:VCALENDAR"].join("\r\n")
  end

  it "is named after its space, else after itself" do
    expect(described_class.new(space: build(:space, name: "Makerspace"), name: "Hours").hours_name).to eq("Makerspace")
    expect(described_class.new(name: "Hours").hours_name).to eq("Hours")
  end

  it "is drawn in its own colour, else in one made from its link" do
    expect(described_class.new(calendar_url: url, color: "#123456").display_color).to eq("#123456")
    expect(described_class.new(calendar_url: url).display_color).to eq(ApplicationController.helpers.generate_color_from_id(url))
  end

  it "lists the linked opening-hours calendars in the order they were added" do
    described_class.create!(calendar_url: url, role: "open_hours", space: create(:space, name: "First"))
    described_class.create!(calendar_url: "https://calendar.example/b.ics", role: "open_hours", space: create(:space, name: "Second"))
    described_class.create!(calendar_url: "", role: "open_hours", space: create(:space))
    described_class.create!(calendar_url: url)

    expect(described_class.open_hours.map(&:hours_name)).to eq(%w[First Second])
  end

  it "sends its feed's occurrences in the window as one source under the feed's id and its colour" do
    allow(IcsFetcher).to receive(:get).with(url, any_args).and_return(ics)
    sources = described_class.new(calendar_url: url, color: "#123456", name: "Hours").feed_sources(week)

    expect(sources.map { |source| source.slice(:id, :color) }).to eq([{ id: Digest::MD5.hexdigest(url), color: "#123456" }])
    expect(sources.sole[:events].map { |row| row.values_at(:title, :start) }).to eq([["Open", "2099-01-05T10:00:00-05:00"]])
    expect(sources.sole[:events].sole[:extendedProps]).to include(name: "Hours")
  end

  it "names the rows as asked" do
    allow(IcsFetcher).to receive(:get).with(url, any_args).and_return(ics)
    rows = described_class.new(calendar_url: url).feed_sources(week, name: "Makerspace").sole[:events]
    expect(rows.sole[:extendedProps]).to include(name: "Makerspace")
  end

  it "sends no source when the server gives no body" do
    allow(IcsFetcher).to receive(:get).with(url, any_args).and_return(nil)
    expect(described_class.new(calendar_url: url).feed_sources(week)).to eq([])
  end
end
