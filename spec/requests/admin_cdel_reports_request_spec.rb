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
    student = create(:user, :student, name: "Cora Student", email: "cora@example.test",
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
      it "#{role} is redirected to / from index and generate and receives no CSV" do
        c18_sign_in(role)
        get admin_cdel_reports_index_path
        expect(response).to redirect_to("/")
        get admin_cdel_reports_generate_path, params: range.merge(visitors: "Dump visitors")
        expect(response).to redirect_to("/")
        expect(response.body).not_to include("cora@example.test")
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
      expect(rows[1][0..2]).to eq([world[:student].id.to_s, "Cora Student", "cora@example.test"])
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
      data = rows.find { |r| r[2] == "cora@example.test" }
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

    it "a range report excludes records made on the end date itself" do
      # the end date is a Date (midnight), so rows created later on the 'To' day fall outside the dump
      create(:user, :student, email: "lastday@example.test", created_at: Time.utc(2026, 3, 31, 12))
      get admin_cdel_reports_generate_path, params: range.merge(new_users: "x")
      expect(csv_rows.map { |r| r[2] }).not_to include("lastday@example.test")
    end

    it "range with a missing or unparseable date is a 500" do
      # params[:start_date].to_date is not guarded, so a missing date (nil) or garbage raises instead of a 400/flash
      get admin_cdel_reports_generate_path, params: { date_format: "range", end_date: "2026-03-31", visitors: "x" }
      expect(response).to have_http_status(:internal_server_error)
      get admin_cdel_reports_generate_path, params: range.merge(start_date: "garbage", visitors: "x")
      expect(response).to have_http_status(:internal_server_error)
    end

    it "no date_format or an unknown semester term: visitors/certifications dump EVERYTHING (nil..nil), new_users is a 500" do
      # start_date/end_date return nil for a missing date_format or unknown term; visitors/certifications silently become unbounded dumps named 'dump--.csv', new_users raises on nil.to_date
      get admin_cdel_reports_generate_path, params: { visitors: "x" }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("CEED_visitors_dump--.csv")
      expect(csv_rows.size).to eq(2)

      get admin_cdel_reports_generate_path,
          params: { date_format: "semester", semester_term: "Spring", semester_year: "2025", certifications: "x" }
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("CEED_certifications_dump--.csv")
      expect(csv_rows.size).to eq(2)

      get admin_cdel_reports_generate_path, params: { new_users: "x" }
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
