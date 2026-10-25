# frozen_string_literal: true

require "rails_helper"

# Chunk 18: the two staff-area xlsx report endpoints that the page crawl skips
# (they are download routes): StaffDashboardController#present_users_report and
# Staff::TrainingSessionsController#training_report. Both inherit
# StaffAreaController#ensure_staff (guest -> login with back_to, regular user ->
# "/" with an alert); training_report adds verify_ownership (owner or admin).
RSpec.describe "Staff xlsx reports", type: :request do
  include Chunk18Helpers

  let(:space) { create(:space, name: "Staff Report Space") }

  describe "GET /staff_dashboard/present_users_report" do
    before do
      present = create(:user, name: "Present Pat", email: "pat@example.test")
      create(:lab_session, space: space, user: present, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
    end

    it "redirects a guest to the login page with back_to" do
      get "/staff_dashboard/present_users_report.xlsx"
      expect(response).to redirect_to(login_path(back_to: "/staff_dashboard/present_users_report.xlsx"))
    end

    it "redirects a regular user to / with an alert and sends no file" do
      c18_sign_in(:regular)
      get "/staff_dashboard/present_users_report.xlsx"
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    %i[staff admin].each do |role|
      it "sends the present-users workbook to #{role} (staff's own space, else the first space)" do
        user = c18_sign_in(role)
        user.update!(space: space)
        get "/staff_dashboard/present_users_report.xlsx"
        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Disposition"]).to match(
          /attachment; filename="Staff Report Space_\d{4}-\d{2}-\d{2}_\d{2}h\d{2}_present_users_report\.xlsx"/
        )
        rows = c18_xlsx_sheets(response.body).fetch("Report")
        expect(rows.first.first).to eq("Present Users")
        expect(rows).to include(["Present Pat", "pat@example.test"])
      end
    end

    it "has no html template: the .html variant is a 406 even for staff" do
      # WART(D-R12): both report actions declare format.html but no present_users_report/training_report template exists, so the html request answers 406 (the page is only reachable as .xlsx)
      c18_sign_in(:staff)
      get "/staff_dashboard/present_users_report"
      expect(response).to have_http_status(:not_acceptable)
    end
  end

  describe "GET /staff/training_sessions/:id/training_report" do
    let(:owner) { create(:user, :staff) }
    let!(:training_session) do
      create(:training_session, user: owner, space: space, course: "ENG9").tap do |ts|
        ts.users << create(:user, name: "Trainee Tom", email: "tom@example.test")
      end
    end
    let(:path) { "/staff/training_sessions/#{training_session.id}/training_report.xlsx" }

    it "redirects a guest to the login page" do
      get path
      expect(response).to redirect_to(login_path(back_to: path))
    end

    it "redirects a regular user to / with an alert" do
      c18_sign_in(:regular)
      get path
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    it "bounces a staff member who is not the session's instructor" do
      c18_sign_in(:staff)
      get path
      expect(response).to redirect_to(new_staff_training_session_path)
      expect(flash[:alert]).to eq("Can't access training session")
    end

    it "sends the xlsx (no filename: default attachment name) to the owning staff member" do
      post login_authentication_path, params: { username_email: owner.username, password: "asa32A353#" }
      get path
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      rows = c18_xlsx_sheets(response.body).fetch("Report")
      expect(rows).to include(["Trainee Tom", "tom@example.test"], %w[Course ENG9])
    end

    it "the .html variant is also a 406 (see D-R12 above)" do
      c18_sign_in(:admin)
      get "/staff/training_sessions/#{training_session.id}/training_report"
      expect(response).to have_http_status(:not_acceptable)
    end

    it "sends the xlsx to any admin" do
      c18_sign_in(:admin)
      get path
      expect(response).to have_http_status(:ok)
      expect(c18_xlsx_sheets(response.body)).to have_key("Report")
    end
  end
end
