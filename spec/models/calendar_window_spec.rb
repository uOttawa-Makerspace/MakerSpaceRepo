# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarWindow do
  def window(from, to) = described_class.parse(from, to)

  it "reads a value with an offset as that instant" do
    w = window("2027-03-14T03:30:00-04:00", "2027-03-15T00:00:00Z")
    expect([w.from.utc.iso8601, w.to.utc.iso8601]).to eq(%w[2027-03-14T07:30:00Z 2027-03-15T00:00:00Z])
  end

  it "reads a value without an offset as Toronto wall time, on either side of a clock change" do
    expect(window("2027-03-13T12:00:00", "2027-03-15T12:00:00").then { |w| [w.from, w.to] }.map(&:iso8601))
      .to eq(%w[2027-03-13T12:00:00-05:00 2027-03-15T12:00:00-04:00])
    expect(window("2027-11-06T12:00:00", "2027-11-08T12:00:00").then { |w| [w.from, w.to] }.map(&:iso8601))
      .to eq(%w[2027-11-06T12:00:00-04:00 2027-11-08T12:00:00-05:00])
  end

  it "reads a plain date as Toronto midnight" do
    expect(window("2027-03-14", "2027-03-15").then { |w| [w.from, w.to] }.map(&:iso8601)).to eq(%w[2027-03-14T00:00:00-05:00 2027-03-15T00:00:00-04:00])
  end

  it "accepts an empty range and the longest range" do
    expect { window("2027-03-14", "2027-03-14") }.not_to raise_error
    expect { window("2027-01-01T00:00:00Z", "2027-04-11T00:00:00Z") }.not_to raise_error
  end

  it "refuses an end before the start, in English and French" do
    expect { window("2027-03-15", "2027-03-14") }.to raise_error(described_class::Invalid, /before its start/)
    I18n.with_locale(:fr) { expect { window("2027-03-15", "2027-03-14") }.to raise_error(described_class::Invalid, /précède/) }
  end

  it "refuses a range of more than 100 days, in English and French" do
    expect { window("2027-01-01T00:00:00Z", "2027-04-11T00:00:01Z") }.to raise_error(described_class::Invalid, /100 days/)
    I18n.with_locale(:fr) { expect { window("2027-01-01", "2027-06-01") }.to raise_error(described_class::Invalid, /100 jours/) }
  end

  it "refuses missing and unreadable values" do
    [[nil, "2027-01-01"], ["", "2027-01-01"], ["2027-01-01", "tomorrow-ish"], ["2027-13-45", "2027-01-01"]].each do |from, to|
      expect { window(from, to) }.to raise_error(described_class::Invalid, /not a valid date/)
    end
  end
end
