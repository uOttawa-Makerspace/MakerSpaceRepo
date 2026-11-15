# frozen_string_literal: true

require "rails_helper"

# Chunk 18: Admin::CdelReportsController (CSV dumps for CDEL) and
# CdelReportGenerator.
#
# Gate: AdminAreaController (before_action :current_user, :ensure_admin). Guests
# get current_user = User.new and are bounced like regular users and staff. The
# dumps contain PII (name, email, student id) and are admin-only.
RSpec.describe "Admin CDEL reports", type: :request do
  include Chunk18Helpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:range) { { date_format: "range", start_date: "2026-03-01", end_date: "2026-03-31" } }

  let!(:world) do
    space = create(:space, name: "Cdel Space")
    student = create(:user, :student, name: "Cora Student", email: "cora@uottawa.ca",
                     username: "corastudent", created_at: march_10)
    training = create(:training, name_en: "Cdel Training")
    session = create(:training_session, space: space, training: training,
                     created_at: march_10, course: "ENG1100", level: "Beginner")
    create(:lab_session, space: space, user: student, created_at: march_10,
                         sign_in_time: march_10, sign_out_time: march_10 + 1.hour)
    create(:certification, user: student, training_session: session, training: training,
                           space: space, created_at: march_10)
    { student: student, space: space, training: training }
  end

  def csv_rows
    CSV.parse(response.body)
  end

  describe "authorization" do
    %i[guest regular staff].each do |role|
      it "#{role} is bounced from index and generate and receives no CSV" do
        c18_sign_in(role)
        get admin_cdel_reports_index_path
        expect_admin_area_bounce(guest: role == :guest)
        get admin_cdel_reports_generate_path, params: range.merge(visitors: "Dump visitors")
        expect_admin_area_bounce(guest: role == :guest)
        expect(response.body).not_to include("cora@uottawa.ca")
      end
    end

    it "admin sees the form with the three dump buttons" do
      c18_sign_in(:admin)
      get admin_cdel_reports_index_path
      expect(response).to have_http_status(:ok)
      %w[visitors certifications new_users].each { |b| expect(response.body).to include(%(name="#{b}")) }
    end
  end

  describe "GET generate (admin)" do
    before { c18_sign_in(:admin) }

    it "visitors: CSV attachment CEED_visitors_dump-<start>-<end>.csv with user, space and sign in/out columns" do
      get admin_cdel_reports_generate_path, params: range.merge(visitors: "Dump visitors")
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include(
        %(attachment; filename="CEED_visitors_dump-2026-03-01-2026-03-31.csv")
      )
      expect(response.headers["Content-Type"]).to start_with("text/csv")
      rows = csv_rows
      expect(rows.first).to eq(%w[users.id users.name users.email users.identity users.student_id users.program
                                   spaces.name lab_sessions.sign_in_time lab_sessions.sign_out_time])
      expect(rows.size).to eq(2)
      expect(rows[1][0..2]).to eq([world[:student].id.to_s, "Cora Student", "cora@uottawa.ca"])
      expect(rows[1][6]).to eq("Cdel Space")
    end

    it "certifications: CSV with the course, level, training and skill columns" do
      get admin_cdel_reports_generate_path, params: range.merge(certifications: "Dump certifications")
      expect(response.headers["Content-Disposition"]).to include("CEED_certifications_dump-2026-03-01-2026-03-31.csv")
      rows = csv_rows
      expect(rows.first.last(6)).to eq(%w[spaces.name training_sessions.course training_sessions.level
                                           training_sessions.created_at trainings.name skills.name])
      expect(rows.size).to eq(2)
      expect(rows[1][6]).to eq("Cdel Space")
      expect(rows[1][7..8]).to eq(%w[ENG1100 Beginner])
    end

    it "new_users: CSV with demographics and login columns (PII: name, email, student id)" do
      get admin_cdel_reports_generate_path, params: range.merge(new_users: "Dump new users")
      expect(response.headers["Content-Disposition"]).to include("CEED_new_users_dump-2026-03-01-2026-03-31.csv")
      rows = csv_rows
      expect(rows.first).to eq(%w[users.id users.name users.email users.identity users.student_id users.program
                                   users.username users.created_at users.last_signed_in_time users.last_seen_at
                                   users.use users.how_heard_about_us users.confirmed])
      data = rows.find { |r| r[2] == "cora@uottawa.ca" }
      expect(data[4]).to eq(world[:student].student_id)
      expect(data[6]).to eq("corastudent")
    end

    it "the first submitted button wins (visitors before certifications before new_users)" do
      get admin_cdel_reports_generate_path, params: range.merge(certifications: "x", new_users: "y")
      expect(response.headers["Content-Disposition"]).to include("CEED_certifications_dump")
    end

    it "semester Fall 2025 is 2025-09-01..2025-12-31, Winter Jan 1..Apr 30, Summer May 1..Aug 31" do
      { "Fall" => %w[2025-09-01 2025-12-31], "Winter" => %w[2025-01-01 2025-04-30], "Summer" => %w[2025-05-01 2025-08-31] }
        .each do |term, (from, to)|
        get admin_cdel_reports_generate_path,
            params: { date_format: "semester", semester_term: term, semester_year: "2025", new_users: "x" }
        expect(response.headers["Content-Disposition"]).to include("CEED_new_users_dump-#{from}-#{to}.csv"), term
      end
    end

    it "answers 400 with an empty body when no dump button was pressed" do
      get admin_cdel_reports_generate_path, params: range
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to be_empty
    end

    context "on a server in another time zone" do
      around do |example|
        server_zone = ENV.fetch("TZ", nil)
        ENV["TZ"] = "Asia/Tokyo"
        example.run
      ensure
        ENV["TZ"] = server_zone
      end

      it "a range report covers the whole From and To days in Toronto" do
        # 21:00 on Feb 28 in Toronto is already March 1 in UTC
        create(:user, :student, email: "eve@uottawa.ca", created_at: Time.zone.local(2026, 2, 28, 21))
        create(:user, :student, email: "firstday@uottawa.ca", created_at: Time.zone.local(2026, 3, 1, 0, 30))
        create(:user, :student, email: "lastday@uottawa.ca", created_at: Time.zone.local(2026, 3, 31, 23, 30))
        create(:user, :student, email: "nextday@uottawa.ca", created_at: Time.zone.local(2026, 4, 1, 0, 30))
        get admin_cdel_reports_generate_path, params: range.merge(new_users: "x")
        emails = csv_rows.map { |r| r[2] }
        expect(emails).to include("firstday@uottawa.ca", "lastday@uottawa.ca", "cora@uottawa.ca")
        expect(emails).not_to include("eve@uottawa.ca", "nextday@uottawa.ca")
      end

      it "a semester report ends at the end of its last day in Toronto" do
        # 23:30 on April 30 in Toronto is already May 1 in UTC
        create(:lab_session, space: world[:space], user: world[:student],
                             created_at: Time.zone.local(2026, 4, 30, 23, 30))
        get admin_cdel_reports_generate_path,
            params: { date_format: "semester", semester_term: "Winter", semester_year: "2026", visitors: "x" }
        expect(csv_rows.size).to eq(3) # the header, the March 10 visit and the April 30 one
      end
    end

    it "range with a missing or unparseable date is a 400 naming the date" do
      get admin_cdel_reports_generate_path, params: { date_format: "range", end_date: "2026-03-31", visitors: "x" }
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Failed to parse start date")
      get admin_cdel_reports_generate_path, params: range.merge(end_date: "garbage", visitors: "x")
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Failed to parse end date")
    end

    it "an inverted range, or one outside the allowed years, is a 400" do
      get admin_cdel_reports_generate_path, params: range.merge(start_date: "2026-04-01", visitors: "x")
      expect(response).to have_http_status(:bad_request)
      get admin_cdel_reports_generate_path, params: range.merge(start_date: "1990-01-01", visitors: "x")
      expect(response).to have_http_status(:bad_request)
    end

    it "no date_format or an unknown semester term is a 400 for every report" do
      %w[visitors certifications new_users].each do |report|
        get admin_cdel_reports_generate_path, params: { report => "x" }
        expect(response).to have_http_status(:bad_request), "#{report} without a date_format"
        expect(response.body).to eq("Choose a semester or a date range")

        get admin_cdel_reports_generate_path,
            params: { date_format: "semester", semester_term: "Spring", semester_year: "2025", report => "x" }
        expect(response).to have_http_status(:bad_request), "#{report} with an unknown term"
        expect(response.body).to eq("Invalid term")
      end
    end

    it "a semester year outside the allowed years is a 400" do
      get admin_cdel_reports_generate_path,
          params: { date_format: "semester", semester_term: "Fall", semester_year: "0", visitors: "x" }
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Invalid year")
    end
  end
end
