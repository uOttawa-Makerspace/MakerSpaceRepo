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

  it "reads Date arguments as whole days in Toronto and keeps a mailer's month window as given" do
    # 21:00 on Feb 28 in Toronto is March 1 in UTC; 23:30 on March 31 is April 1
    early = create(:user, :student, created_at: Time.zone.local(2026, 2, 28, 21))
    late = create(:user, :student, created_at: Time.zone.local(2026, 3, 31, 23, 30))
    names = ->(report) { CSV.parse(report[:data]).drop(1).map { |r| r[1] } }
    expect(names.call(described_class.generate_new_users_report(from, to))).to eq([late.name])
    month = Time.zone.local(2026, 3, 1)
    expect(names.call(described_class.generate_new_users_report(month, month.end_of_month))).to eq([late.name])
    expect(names.call(described_class.generate_new_users_report(from - 1, to))).to eq([early.name, late.name])
  end

  it "new_users filename uses to_date, the others use the raw argument in the name" do
    expect(described_class.generate_new_users_report(from.to_datetime, to.to_datetime)[:filename])
      .to eq("CEED_new_users_dump-2026-03-01-2026-03-31.csv")
    expect(described_class.generate_visitors_report(from.to_datetime, to.to_datetime)[:filename])
      .to start_with("CEED_visitors_dump-2026-03-01T00:00:00")
  end

  it "writes a text field that starts like a formula with a leading quote, and leaves other fields as they are" do
    user = create(:user, :student, created_at: march_10)
    user.update_columns(name: '=HYPERLINK("http://example.test","x")', how_heard_about_us: "+1+1",
                        use: "-2", program: "@SUM(1)", email: "plain@example.test")
    header, row = CSV.parse(described_class.generate_new_users_report(from, to)[:data])
    field = header.zip(row).to_h
    expect(field.values_at("users.name", "users.how_heard_about_us", "users.use", "users.program"))
      .to eq(["'=HYPERLINK(\"http://example.test\",\"x\")", "'+1+1", "'-2", "'@SUM(1)"])
    expect(field.values_at("users.id", "users.email", "users.confirmed"))
      .to eq([user.id.to_s, "plain@example.test", user.confirmed.to_s])
    expect(field["users.created_at"]).to eq(user.created_at.to_s)
  end

  it "keeps the visits, certifications and sign-up of a soft-deleted user in the reports" do
    space = create(:space, name: "S1")
    user = create(:user, :student, name: "Deleted Visitor", created_at: march_10)
    create(:lab_session, space: space, user: user, created_at: march_10)
    create(:certification, :basic_training, user_id: user.id, created_at: march_10)
    user.soft_delete!
    visitors, certifications, new_users = described_class.generate_all_reports(from, to).map { |r| CSV.parse(r[:data]) }
    expect(visitors.size).to eq(2)
    expect(visitors[1][1]).to eq("Deleted Visitor")
    expect(certifications.size).to eq(2)
    expect(new_users.flatten).to include(user.username)
  end
end
