# frozen_string_literal: true

require "rails_helper"

# Where the year of study is shown and reported: the profile, the profile and
# admin edit forms, the volunteer list, the JSON of the legacy profile and of
# /api/v1/users/:username, and the new users report (on screen and in the
# spreadsheet).
RSpec.describe "Year of study shown and reported", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  # Entered on 2026-02-15 for an account created in March 2024.
  let!(:student) do
    travel_to(Time.zone.local(2026, 2, 15))
    create(:user, :volunteer_with_volunteer_program, :student, year_of_study: "3",
                                                               created_at: Time.zone.local(2024, 3, 10))
  end

  before { block_external_http! }
  after { travel_back }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def page = Nokogiri::HTML(response.body)
  def selected_year = page.at_css("select[name='user[year_of_study]'] option[selected]")&.[]("value")
  def profile_year = page.xpath("//span[text()='Year of study']/following-sibling::span[1]").text
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }

  def api_year(viewer)
    get "/api/v1/users/#{student.username}", headers: { "ACCEPT" => "application/json" }.merge(auth(viewer))
    response.parsed_body["user"]["year_of_study"]
  end

  def legacy_json_year(viewer)
    login!(viewer)
    get user_path(student.username), headers: { "ACCEPT" => "application/json" }
    response.parsed_body["user"]["year_of_study"]
  end

  def shown_years(viewer)
    login!(viewer)
    get user_path(student.username)
    shown = { profile: profile_year }
    get edit_admin_user_path(student)
    shown[:admin_form] = selected_year
    get volunteer_list_volunteers_path
    shown[:volunteer_list] = response.body.include?("Year #{shown[:profile]}")
    shown
  end

  def own_form_year
    login!(student)
    get settings_profile_path
    selected_year
  end

  def report_rows
    window = [Time.zone.local(2024, 3, 1), Time.zone.local(2024, 3, 31).end_of_day]
    package = ReportGenerator.generate_new_users_report(*window)
    package.workbook.worksheets.flat_map { |sheet| sheet.rows.map { |row| row.cells.map(&:value) } }
  end

  context "before the student's next move up" do
    it "shows the year as entered everywhere" do
      expect(shown_years(admin)).to eq(profile: "3", admin_form: "3", volunteer_list: true)
      expect(own_form_year).to eq("3")
      expect(api_year(admin)).to eq("3")
      expect(legacy_json_year(admin)).to eq("3")
      expect(student.reload.identity_readable).to eq("3rd Year Undergraduate")
    end

    it "reports it in the new users spreadsheet" do
      rows = report_rows
      expect(rows).to include([3, 1])
      # the Report sheet's Year of Study column (the spreadsheet stores it as a number)
      expect(rows.find { |row| row.include?(student.username) }[6]).to eq(3)
    end

    it "charts it in the new users report" do
      login!(admin)
      get admin_report_generator_index_path,
          params: { report_type: "new_users", start_date: "2024-03-01", end_date: "2024-03-31" }
      expect(response.body).to include("[[3,1]]")
    end
  end

  context "after the student's next move up, on the first of the creation month" do
    before { travel_to(Time.zone.local(2026, 3, 1, 9)) }

    it "shows the current year everywhere and keeps the entered one in the legacy column" do
      expect(shown_years(admin)).to eq(profile: "4", admin_form: "4", volunteer_list: true)
      expect(own_form_year).to eq("4")
      expect(api_year(admin)).to eq("4")
      expect(legacy_json_year(admin)).to eq("4")
      expect(student.reload.identity_readable).to eq("4th Year Undergraduate")
      expect(student.year_of_study).to eq("3")
    end

    it "reports the current year in the new users spreadsheet and chart" do
      rows = report_rows
      expect(rows).to include([4, 1])
      expect(rows.find { |row| row.include?(student.username) }[6]).to eq(4)
      login!(admin)
      get admin_report_generator_index_path,
          params: { report_type: "new_users", start_date: "2024-03-01", end_date: "2024-03-31" }
      expect(response.body).to include("[[4,1]]")
    end
  end

  context "once the student is Alumni" do
    before { travel_to(Time.zone.local(2032, 3, 2)) }

    it "offers Alumni in both forms, chosen, so saving another field keeps it" do
      expect(own_form_year).to eq("Alumni")
      login!(admin)
      get edit_admin_user_path(student)
      expect(selected_year).to eq("Alumni")
      login!(student)
      patch user_path(student.username), params: { user: { name: "New Name", year_of_study: "Alumni" } }
      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(student.reload.current_year_of_study).to eq("Alumni")
    end
  end

  describe "setting the year records it as the new reference point" do
    def reference(user)
      user.reload.attributes.values_at("year_of_study", "year_of_study_entered", "year_of_study_set_on",
                                       "year_of_study_set_by")
    end

    before { travel_to(Time.zone.local(2026, 5, 20, 10)) }

    it "on sign-up" do
      attrs = FactoryBot.attributes_for(:user, :regular_user, :student, password: password, year_of_study: "2")
      post users_path, params: { user: attrs }
      expect(reference(User.find_by!(username: attrs[:username]))).to eq(["2", "2", Date.new(2026, 5, 20), "entered"])
    end

    it "from the profile form" do
      login!(student)
      patch user_path(student.username), params: { user: { year_of_study: "5" } }
      expect(reference(student)).to eq(["5", "5", Date.new(2026, 5, 20), "entered"])
      travel_to(Time.zone.local(2027, 3, 1))
      expect(student.reload.current_year_of_study).to eq("6")
    end

    it "from the admin edit form" do
      login!(admin)
      patch admin_user_path(student), params: { user: { year_of_study: "6" } }
      expect(reference(student)).to eq(["6", "6", Date.new(2026, 5, 20), "entered"])
    end
  end
end
