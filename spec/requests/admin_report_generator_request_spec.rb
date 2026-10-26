# frozen_string_literal: true

require "rails_helper"

# Chunk 18: characterization of Admin::ReportGeneratorController.
#
# Existing spec/controllers/admin/report_generator_controller_spec.rb pins the
# flash/400 paths of #generate and the xlsx content-type per type. This spec adds
# what it lacks: the role matrix (guest/regular/staff/admin) over all three
# actions, the redirect contract of #generate, the rendered #index for every
# dispatched report type, the XLSX body contract, and the error paths.
#
# Gate (AdminAreaController): before_action :current_user, :ensure_admin. Guests
# get current_user = User.new, so they hit ensure_admin and are redirected to "/"
# exactly like regular users and staff. Reports contain PII (names, emails) but
# only admins can reach them (no severity-1 finding here).
#
# Report types dispatched by #index / accepted by #generate (10):
#   visitors trainings certifications new_users training_attendees new_projects
#   visits_by_hour kit_purchased popular_hours frequent_visitors
# #generate_spreadsheet (xlsx) supports only 8 of them (no popular_hours, no
# frequent_visitors).

RSpec.describe "Admin report generator", type: :request do
  include Chunk18Helpers

  REPORT_TYPES = %w[
    certifications new_projects new_users trainings training_attendees visitors
    visits_by_hour kit_purchased popular_hours frequent_visitors
  ].freeze
  XLSX_TYPES = (REPORT_TYPES - %w[popular_hours frequent_visitors]).freeze

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:range) { { start_date: "2026-03-01", end_date: "2026-03-31" } }

  # One record per report-relevant model, all created on 2026-03-10.
  let!(:world) do
    space = create(:space, name: "Report Space")
    visitor = create(:user, :student, name: "Vera Visitor", email: "vera@example.test",
                     created_at: march_10)
    create(:lab_session, space: space, user: visitor, created_at: march_10,
                         sign_in_time: march_10, sign_out_time: march_10 + 2.hours)
    training = create(:training, name_en: "Laser Basics")
    session = create(:training_session, space: space, training: training,
                     created_at: march_10)
    session.users << visitor
    create(:certification, user: visitor, training_session: session, training: training,
                           space: space, created_at: march_10)
    create(:repository, created_at: march_10)
    project = create(:proficient_project, title: "Report Kit Project")
    create(:project_kit, user: visitor, proficient_project: project, created_at: march_10)
    { space: space, visitor: visitor, training: training, project: project }
  end

  describe "authorization (all three actions)" do
    {
      "GET index" => -> { get admin_report_generator_index_path },
      "POST generate" => -> { post admin_report_generator_generate_path, params: { range_type: "all_time", type: "visitors" } },
      "GET generate_spreadsheet" => -> { get admin_report_generator_generate_spreadsheet_path, params: { type: "visitors" } }
    }.each do |label, call|
      %i[guest regular staff].each do |role|
        it "#{label}: #{role} is redirected to / and gets no report" do
          c18_sign_in(role)
          instance_exec(&call)
          expect(response).to redirect_to("/")
          expect(response.body).not_to include("Vera Visitor")
          expect(response.media_type).not_to include("xlsx")
        end
      end

      it "#{label}: admin passes the gate" do
        c18_sign_in(:admin)
        instance_exec(&call)
        expect(response).not_to redirect_to("/")
      end
    end
  end

  describe "GET index" do
    before { c18_sign_in(:admin) }

    it "renders the form with all ten report types and no report when no type is chosen" do
      get admin_report_generator_index_path
      expect(response).to have_http_status(:ok)
      REPORT_TYPES.each { |t| expect(response.body).to include(%(id="type_#{t}")) }
      expect(response.body).not_to include('id="report"')
    end

    XLSX_TYPES.each do |type|
      # N+1 pinned: see defects D-PERF-R01 (certifications/trainings/training_attendees load associations they never use)
      pinned = %w[certifications trainings training_attendees].include?(type)
      it "renders the #{type} report for a date range", skip_bullet: pinned do
        get admin_report_generator_index_path, params: range.merge(report_type: type)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="report"')
      end
    end

    # N+1 pinned: see defects D-PERF-R01
    it "renders every dispatched report type without dates (all time), except frequent_visitors", skip_bullet: true do
      (REPORT_TYPES - %w[frequent_visitors]).each do |type|
        get admin_report_generator_index_path, params: { report_type: type }
        expect(response).to have_http_status(:ok), "#{type}: #{response.status}"
      end
    end

    it "counts the seeded data in the visitors report" do
      get admin_report_generator_index_path, params: range.merge(report_type: "visitors")
      expect(response.body).to include("Report Space")
      expect(response.body).to include("Undergrad")
    end

    it "lists the seeded training in the trainings report" do
      get admin_report_generator_index_path, params: range.merge(report_type: "trainings")
      expect(response.body).to include("Laser Basics")
    end

    it "counts the purchased kit in the kit_purchased report" do
      get admin_report_generator_index_path, params: range.merge(report_type: "kit_purchased")
      expect(response.body).to include("Displaying 1 project kit")
    end

    it "answers an unknown report type with a bare 400 'Unknown report type' (no layout)" do
      get admin_report_generator_index_path, params: range.merge(report_type: "nope")
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Unknown report type")
      expect(response.media_type).to eq("text/plain")
    end

    it "frequent_visitors without dates is a 500" do
      # WART(D-R04): frequent_visitors calls params[:start_date].to_datetime with no presence check, so choosing it without a date range raises NoMethodError
      get admin_report_generator_index_path, params: { report_type: "frequent_visitors" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "frequent_visitors with dates renders" do
      get admin_report_generator_index_path, params: range.merge(report_type: "frequent_visitors")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Report Space")
    end

    it "popular_hours without dates renders the all-time partial" do
      get admin_report_generator_index_path, params: { report_type: "popular_hours" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying all-time popular hours")
    end

    it "popular_hours all-time draws one weekday chart per day that has PopularHour rows, per space" do
      create(:popular_hour, space: world[:space], day: 2, hour: 10, mean: 3.5)
      get admin_report_generator_index_path, params: { report_type: "popular_hours" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Displaying all-time popular hours in Report Space")
      expect(response.body).to include('id="Report-Space-2"')
      expect(response.body).not_to include('id="Report-Space-3"')
    end

    it "popular_hours WITH dates shows 'Invalid report type specified' instead of the per-period report" do
      # WART(D-R05): the controller rewrites params[:report_type] to 'popular_hours_per_period', which the index view's allow-list does not contain, so the per-period report (its partial exists) is never rendered
      get admin_report_generator_index_path, params: range.merge(report_type: "popular_hours")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Invalid report type specified")
      expect(response.body).not_to include("Displaying popular hours from")
      expect(response.body).not_to include('id="report"')
    end

    it "an unparseable date string reaches SQL and is a 500" do
      # WART(D-R02): dates are never parsed or validated for the html report; "abc" reaches the SQL range and Postgres rejects it
      get admin_report_generator_index_path,
          params: { start_date: "abc", end_date: "def", report_type: "certifications" }
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "POST generate" do
    before { c18_sign_in(:admin) }

    def redirect_query
      Rack::Utils.parse_query(URI(response.location).query)
    end

    it "semester/winter redirects to the index with Jan 1 - Apr 30 and the selection echoed back" do
      post admin_report_generator_generate_path,
           params: { range_type: "semester", term: "winter", year: "2026", type: "visitors" }
      expect(response).to have_http_status(:found)
      expect(URI(response.location).path).to eq("/admin/report_generator")
      expect(URI(response.location).fragment).to eq("report")
      expect(redirect_query).to include(
        "report_type" => "visitors", "range_type" => "semester", "term" => "winter", "year" => "2026"
      )
      expect(redirect_query["start_date"]).to start_with("2026-01-01T00:00:00")
      expect(redirect_query["end_date"]).to start_with("2026-04-30T23:59:59")
      expect(flash[:notice]).to eq("Successfully generated visitors report")
    end

    it "maps summer to May 1 - Aug 31 and fall to Sep 1 - Dec 31" do
      post admin_report_generator_generate_path,
           params: { range_type: "semester", term: "summer", year: "2026", type: "new_users" }
      expect([redirect_query["start_date"][0, 10], redirect_query["end_date"][0, 10]]).to eq(%w[2026-05-01 2026-08-31])
      expect(flash[:notice]).to eq("Successfully generated new users report")
      post admin_report_generator_generate_path,
           params: { range_type: "semester", term: "fall", year: "2026", type: "kit_purchased" }
      expect([redirect_query["start_date"][0, 10], redirect_query["end_date"][0, 10]]).to eq(%w[2026-09-01 2026-12-31])
    end

    it "date_range redirects with the parsed from/to as whole-day datetimes" do
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", from_date: "2026-03-01", to_date: "2026-03-31", type: "trainings" }
      expect(redirect_query["start_date"]).to start_with("2026-03-01T00:00:00")
      expect(redirect_query["end_date"]).to start_with("2026-03-31T23:59:59")
      expect(redirect_query["range_type"]).to eq("date_range")
    end

    it "all_time redirects with blank start/end dates (the index then reports everything)" do
      post admin_report_generator_generate_path, params: { range_type: "all_time", type: "popular_hours" }
      expect(response).to have_http_status(:found)
      expect(redirect_query).to include("report_type" => "popular_hours", "range_type" => "all_time")
      expect(redirect_query["start_date"].to_s).to eq("")
      expect(redirect_query["end_date"].to_s).to eq("")
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "accepts every one of the ten report types" do
      REPORT_TYPES.each do |type|
        post admin_report_generator_generate_path, params: { range_type: "all_time", type: type }
        expect(response).to have_http_status(:found), type
      end
    end

    {
      "an unknown range type" => [{ range_type: "decade", type: "visitors" }, "Invalid range type"],
      "no range type" => [{ type: "visitors" }, "Invalid range type"],
      "a semester without a year" => [{ range_type: "semester", term: "fall", type: "visitors" }, "Invalid year"],
      "a zero/non-numeric year" => [{ range_type: "semester", term: "fall", year: "abc", type: "visitors" }, "Invalid year"],
      "an unknown term" => [{ range_type: "semester", term: "spring", year: "2026", type: "visitors" }, "Invalid term"],
      "an unknown report type" => [{ range_type: "all_time", type: "payroll" }, "Unknown report type"],
      "a missing report type" => [{ range_type: "all_time" }, "Unknown report type"]
    }.each do |label, (params, message)|
      it "answers #{label} with 400 '#{message}'" do
        post admin_report_generator_generate_path, params: params
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to eq(message)
      end
    end

    it "validates the range type before the report type" do
      post admin_report_generator_generate_path, params: { range_type: "x", type: "payroll" }
      expect(response.body).to eq("Invalid range type")
    end

    it "accepts a huge year (no upper bound)" do
      post admin_report_generator_generate_path,
           params: { range_type: "semester", term: "fall", year: "9999", type: "visitors" }
      expect(response).to have_http_status(:found)
      expect(redirect_query["start_date"]).to start_with("9999-09-01")
    end

    it "date_range accepts an inverted range (end before start) with no complaint" do
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", from_date: "2026-03-31", to_date: "2026-03-01", type: "visitors" }
      expect(response).to have_http_status(:found)
    end

    it "date_range with an unparseable or missing date is a 500 instead of the intended message" do
      # WART(D-R01): `rescue ParseError` names a constant that does not exist (Date::Error is what Date.parse raises), so the rescue itself raises NameError and bad/missing dates 500 instead of "Failed to parse start date"
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", from_date: "garbage", to_date: "2026-03-01", type: "visitors" }
      expect(response).to have_http_status(:internal_server_error)
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", to_date: "2026-03-01", type: "visitors" }
      expect(response).to have_http_status(:internal_server_error)
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", from_date: "2026-03-01", to_date: "garbage", type: "visitors" }
      expect(response).to have_http_status(:internal_server_error)
    end

    # N+1 pinned: see defects D-PERF-R01
    it "the redirected index chain renders the chosen report end to end", skip_bullet: true do
      post admin_report_generator_generate_path,
           params: { range_type: "date_range", from_date: "2026-03-01", to_date: "2026-03-31", type: "trainings" }
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Laser Basics")
    end
  end

  describe "GET generate_spreadsheet" do
    before { c18_sign_in(:admin) }

    def fetch_xlsx(type, params = {})
      get admin_report_generator_generate_spreadsheet_path, params: { type: type }.merge(params)
      expect(response).to have_http_status(:ok), "#{type}: #{response.status}"
    end

    XLSX_TYPES.each do |type|
      it "#{type}: sends an application/xlsx attachment named <type>_<start>_<end>.xlsx that opens as a workbook" do
        fetch_xlsx(type, range)
        expect(response.headers["Content-Type"]).to eq("application/xlsx")
        expect(response.headers["Content-Disposition"]).to include(
          %(attachment; filename="#{type}_2026-03-01_2026-03-31.xlsx")
        )
        sheets = c18_xlsx_sheets(response.body)
        expect(sheets).not_to be_empty
        expect(response.body.byteslice(0, 2)).to eq("PK")
      end
    end

    # Midday Eastern, so DateTime.now's server/UTC date and Date.current agree.
    it "defaults to 2015-06-01 .. today when no dates are given" do
      travel_to(Time.zone.now.change(hour: 12))
      fetch_xlsx("kit_purchased")
      expect(response.headers["Content-Disposition"]).to include(
        "kit_purchased_2015-06-01_#{Date.current.strftime("%Y-%m-%d")}.xlsx"
      )
    end

    # WART(D-R26): the default range ends at DateTime.now (server/UTC), so after 20:00 Eastern "today" is tomorrow's date
    it "ends the default range on the UTC date in the Eastern evening" do
      travel_to(Time.zone.now.change(hour: 21))
      fetch_xlsx("kit_purchased")
      expect(response.headers["Content-Disposition"]).to include(
        "kit_purchased_2015-06-01_#{(Date.current + 1).strftime("%Y-%m-%d")}.xlsx"
      )
    end

    it "kit_purchased: title, from/to, header row and one data row per kit" do
      fetch_xlsx("kit_purchased", range)
      rows = c18_xlsx_sheets(response.body).fetch("Report")
      expect(rows[0].first).to eq("Purchased kits")
      expect(rows[1].first(2)).to eq(%w[From 2026-03-01])
      expect(rows[2].first(2)).to eq(%w[To 2026-03-31])
      expect(rows[4]).to eq(["Kit name", "User", "Date", "Delivery Status"])
      expect(rows[5][0]).to eq(world[:project].title)
      expect(rows[5][1]).to eq("Vera Visitor")
      expect(rows[5][3]).to eq("Not yet delivered")
      expect(rows.size).to eq(6)
    end

    # N+1 pinned: see defects D-PERF-R02 (kit report loads proficient_project and user per kit)
    it "kit_purchased: a delivered kit says Delivered", skip_bullet: true do
      create(:project_kit, :"delivered", user: world[:visitor], created_at: march_10)
      fetch_xlsx("kit_purchased", range)
      statuses = c18_xlsx_sheets(response.body).fetch("Report")[5..].map { |r| r[3] }
      expect(statuses).to match_array(["Not yet delivered", "Delivered"])
    end

    it "visitors: an Overview sheet first, one sheet per visited space, and a Programs sheet" do
      fetch_xlsx("visitors", range)
      sheets = c18_xlsx_sheets(response.body)
      expect(sheets.keys).to eq(["Report", "Report Space", "Programs"])
      overview = sheets["Report"]
      expect(overview.first.first).to eq("Visitors")
      expect(overview).to include(["CEED-Wide unique visitors", 1, nil, nil, nil, nil])
      expect(overview).to include(["CEED-Wide total visitors", 1, nil, nil, nil, nil])
      expect(sheets["Report Space"][4].first).to eq("Report for Report Space")
      expect(sheets["Programs"]).to eq([["program", "Distinct Users", nil, "Total Visits"],
                                        ["BASc in Software Engineering", 1, nil, 1]])
    end

    it "new_users: a Demographics sheet with the total and the identity breakdown" do
      fetch_xlsx("new_users", range)
      rows = c18_xlsx_sheets(response.body).fetch("Demographics")
      expect(rows[0].first).to eq("New Users Breakdown")
      expect(rows).to include(["Total new users", 1])
      expect(rows.map(&:first)).to include("Undergrad")
    end

    it "visits_by_hour: header row Date + hour columns and a row per day with the visit counts" do
      fetch_xlsx("visits_by_hour", range)
      rows = c18_xlsx_sheets(response.body).fetch("Sheet1")
      expect(rows[0].first).to eq("Visitors by Hour")
      expect(rows[1].first(2)).to eq(%w[From 2026-03-01])
      hour = march_10.localtime.hour
      expect(rows[4].compact).to eq(["Date", "%02i:00" % hour])
      expect(rows[5..].size).to eq(31) # 2026-03-01 .. 2026-03-31 inclusive
      expect(rows.find { |r| r.first == "2026-03-10" }[1]).to eq(1)
      expect(rows.find { |r| r.first == "2026-03-09" }[1]).to eq(0)
    end

    it "an empty range still yields a workbook (header row only)" do
      fetch_xlsx("visits_by_hour", start_date: "2020-01-01", end_date: "2020-01-02")
      rows = c18_xlsx_sheets(response.body).fetch("Sheet1")
      expect(rows[4].compact).to eq(["Date"])
    end

    it "the end date is exclusive of its own day (midnight cut-off)" do
      # WART(D-R03): end_date is parsed with Date.parse(..).to_datetime, i.e. 00:00, without end_of_day, so records made on the 'To' date are left out of the xlsx while the html report (end_of_day) includes them
      create(:project_kit, user: world[:visitor], created_at: Time.utc(2026, 3, 31, 12), proficient_project: create(:proficient_project, title: "Last Day Kit"))
      fetch_xlsx("kit_purchased", range)
      titles = c18_xlsx_sheets(response.body).fetch("Report")[5..].map(&:first)
      expect(titles).to eq([world[:project].title])
    end

    it "popular_hours and frequent_visitors have no spreadsheet (400) although the index offers them" do
      # WART(D-R06): the index lists popular_hours and frequent_visitors as report types but generate_spreadsheet has no branch for them; the 400 is a bare text body
      %w[popular_hours frequent_visitors].each do |type|
        fetch_ok = get admin_report_generator_generate_spreadsheet_path, params: { type: type }
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to eq("Unknown report type")
        expect(fetch_ok).to eq(400)
      end
    end

    it "answers an unknown or missing type with 400 'Unknown report type'" do
      get admin_report_generator_generate_spreadsheet_path, params: { type: "payroll" }
      expect(response).to have_http_status(:bad_request)
      get admin_report_generator_generate_spreadsheet_path
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq("Unknown report type")
    end

    it "an unparseable start or end date is a 500" do
      # WART(D-R02): Date.parse is not rescued in generate_spreadsheet, so a bad date raises instead of a 400
      get admin_report_generator_generate_spreadsheet_path, params: { type: "visitors", start_date: "garbage" }
      expect(response).to have_http_status(:internal_server_error)
      get admin_report_generator_generate_spreadsheet_path, params: { type: "visitors", end_date: "garbage" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "does not validate the order of the range (end before start gives an empty workbook)" do
      fetch_xlsx("visitors", start_date: "2026-04-01", end_date: "2026-03-01")
      sheets = c18_xlsx_sheets(response.body)
      expect(sheets.keys).to eq(["Report", "Programs"])
    end

    it "has no cap on the date range: a 36-year visits_by_hour report is generated, one row per day" do
      # WART(D-R07): no maximum span, so one request can make the server build a workbook with a row per day for any range (the unbounded range is also unrestricted for admins only)
      fetch_xlsx("visits_by_hour", start_date: "1990-01-01", end_date: "2026-01-01")
      rows = c18_xlsx_sheets(response.body).fetch("Sheet1")
      expect(rows[5..].size).to eq((Date.new(2026, 1, 1) - Date.new(1990, 1, 1)).to_i + 1)
    end
  end
end
