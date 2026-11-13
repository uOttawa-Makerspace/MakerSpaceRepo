# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarWindow do
  let(:toronto) { RecurrenceRule::ZONE }

  def window(start, finish)
    described_class.from_params(ActionController::Parameters.new(start: start, end: finish))
  end

  describe ".from_params" do
    it "keeps everything when neither bound is given" do
      expect(described_class.from_params(ActionController::Parameters.new({}))).to be(CalendarWindow::ALL)
      expect(CalendarWindow::ALL).to be_a(CalendarWindow::Unbounded)
    end

    it "reads a time without an offset as Toronto wall time, as FullCalendar sends it" do
      spring = window("2027-03-14T00:00:00", "2027-03-21T00:00:00")

      expect(spring.from).to eq(toronto.local(2027, 3, 14))
      expect(spring.to).to eq(Time.utc(2027, 3, 21, 4))
    end

    it "reads a time with an offset as that instant and a date alone as Toronto midnight" do
      expect(window("2027-03-14T00:00:00-04:00", "2027-03-15").from).to eq(Time.utc(2027, 3, 14, 4))
      expect(window("2027-03-14T00:00:00Z", "2027-03-15").to).to eq(toronto.local(2027, 3, 15))
    end

    it "accepts 100 local days across the clocks going back (an hour longer in real time)" do
      expect(window("2026-11-01", "2027-02-09").to).to eq(toronto.local(2027, 2, 9))
    end

    {
      "only a start" => ["2027-03-14", nil],
      "only an end" => [nil, "2027-03-14"],
      "an unreadable start" => ["not a date", "2027-03-14"],
      "an impossible date" => ["2027-13-45", "2027-03-14"],
      "an end before the start" => ["2027-03-15", "2027-03-14"]
    }.each do |case_name, (start, finish)|
      it "refuses #{case_name}, saying why" do
        expect { window(start, finish) }.to raise_error(CalendarWindow::Invalid, I18n.t("errors.calendar.window_invalid"))
      end
    end

    it "refuses a window longer than 100 days" do
      expect { window("2027-03-01", "2027-06-10T02:00:00") }
        .to raise_error(CalendarWindow::Invalid, "The calendar can show at most 100 days at a time.")
    end
  end

  describe "#records" do
    let(:user) { create(:user, :staff) }
    let(:week) { window("2027-03-14", "2027-03-21") }

    def unavailability(starts, ends, rule = nil)
      create(:staff_unavailability, user: user, start_time: starts, end_time: ends, recurrence_rule: rule)
    end

    it "keeps one-offs that overlap the window, and series that start before its end" do
      inside = unavailability(toronto.local(2027, 3, 16, 9), toronto.local(2027, 3, 16, 10))
      across_start = unavailability(toronto.local(2027, 3, 13, 22), toronto.local(2027, 3, 14, 2))
      ending_at_start = unavailability(toronto.local(2027, 3, 13, 22), toronto.local(2027, 3, 14))
      unavailability(toronto.local(2027, 3, 1, 9), toronto.local(2027, 3, 1, 10))
      unavailability(toronto.local(2027, 3, 21), toronto.local(2027, 3, 21, 1))
      series = unavailability(toronto.local(2027, 1, 4, 9), toronto.local(2027, 1, 4, 10), "RRULE:FREQ=WEEKLY;BYDAY=MO")
      unavailability(toronto.local(2027, 3, 22, 9), toronto.local(2027, 3, 22, 10), "RRULE:FREQ=WEEKLY;BYDAY=MO")

      expect(week.records(StaffUnavailability.all)).to contain_exactly(inside, across_start, ending_at_start, series)
    end

    it "keeps every record with no window" do
      old = unavailability(toronto.local(2020, 3, 1, 9), toronto.local(2020, 3, 1, 10))

      expect(CalendarWindow::ALL.records(StaffUnavailability.all)).to eq([old])
    end
  end

  describe "#entries" do
    let(:week) { window("2027-03-14", "2027-03-21") }
    let(:series) { RecurringSeries.new(rule: "RRULE:FREQ=DAILY", starts_at: toronto.local(2026, 1, 1, 9), ends_at: toronto.local(2026, 1, 1, 10)) }

    def entry(starts, ends, series = nil)
      ImportedCalendar::Entry.new(uid: "uid", recurrence_id: nil, summary: "", description: "", all_day: false,
                                  starts_at: starts, ends_at: ends, series: series)
    end

    it "keeps one-offs that overlap the window, one with no end at its start, and every series" do
      inside = entry(toronto.local(2027, 3, 15, 9), toronto.local(2027, 3, 15, 10))
      moment = entry(toronto.local(2027, 3, 14), nil)
      repeating = entry(toronto.local(2026, 1, 1, 9), toronto.local(2026, 1, 1, 10), series)
      before = entry(toronto.local(2027, 3, 13, 9), toronto.local(2027, 3, 13, 10))
      after = entry(toronto.local(2027, 3, 21), toronto.local(2027, 3, 21, 1))
      earlier_moment = entry(toronto.local(2027, 3, 13, 23), nil)

      expect(week.entries([inside, moment, repeating, before, after, earlier_moment])).to eq([inside, moment, repeating])
    end

    it "keeps every entry with no window" do
      old = entry(toronto.local(2020, 3, 13, 9), toronto.local(2020, 3, 13, 10))

      expect(CalendarWindow::ALL.entries([old])).to eq([old])
    end
  end
end
