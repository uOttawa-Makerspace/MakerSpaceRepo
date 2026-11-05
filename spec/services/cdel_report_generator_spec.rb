# frozen_string_literal: true

require "rails_helper"

# Chunk 18: CdelReportGenerator returns { data: <csv string>, filename: } (also
# used by the periodic MsrMailer, whose delivery is pinned in the mailer specs).
RSpec.describe CdelReportGenerator do
  let(:from) { Date.new(2026, 3, 1) }
  let(:to) { Date.new(2026, 3, 31) }
  let(:march_10) { Time.utc(2026, 3, 10, 15) }

  it "generate_all_reports returns visitors, certifications and new users in that order" do
    reports = described_class.generate_all_reports(from, to)
    expect(reports.map { |r| r[:filename] }).to eq(
      %w[CEED_visitors_dump-2026-03-01-2026-03-31.csv
         CEED_certifications_dump-2026-03-01-2026-03-31.csv
         CEED_new_users_dump-2026-03-01-2026-03-31.csv]
    )
    expect(reports).to all(include(:data, :filename))
  end

  it "with no data every report is just its header row" do
    described_class.generate_all_reports(from, to).first(2).each do |report|
      expect(CSV.parse(report[:data]).size).to eq(1)
    end
  end

  it "visitors drops lab sessions without a user or a space (inner joins) and orders by created_at" do
    space = create(:space, name: "S1")
    first = create(:user, :student, name: "First Visitor")
    second = create(:user, :student, name: "Second Visitor")
    create(:lab_session, space: space, user: second, created_at: march_10 + 1.day)
    create(:lab_session, space: space, user: first, created_at: march_10)
    LabSession.new(user: first, created_at: march_10).save!(validate: false) # no space
    rows = CSV.parse(described_class.generate_visitors_report(from, to)[:data])
    expect(rows.size).to eq(3)
    expect(rows[1][1]).to eq("First Visitor")
    expect(rows[2][1]).to eq("Second Visitor")
  end

  it "visitors renders NULL columns as empty fields and the range is inclusive of the 'to' date's midnight" do
    user = create(:user, :student)
    create(:lab_session, user: user, created_at: march_10, sign_in_time: nil, sign_out_time: nil)
    row = CSV.parse(described_class.generate_visitors_report(from, to)[:data])[1]
    expect(row[-2..]).to eq([nil, nil])
  end

  it "new_users filename uses to_date, the others use the raw argument in the name" do
    expect(described_class.generate_new_users_report(from.to_datetime, to.to_datetime)[:filename])
      .to eq("CEED_new_users_dump-2026-03-01-2026-03-31.csv")
    expect(described_class.generate_visitors_report(from.to_datetime, to.to_datetime)[:filename])
      .to start_with("CEED_visitors_dump-2026-03-01T00:00:00")
  end
end
