# frozen_string_literal: true

require "rails_helper"

# Staff::ProficientProjectSessionsController#show. StaffAreaController gates on
# staff/admin before the action runs, so the action's own `staff?` redirect to
# development_programs_path is unreachable. Only show exists; the nested
# certify_participant route has no action.

RSpec.describe "Staff proficient project sessions", type: :request do
  include SpacesSpecHelpers

  let!(:pps) { create(:proficient_project_session, level: "Beginner") }

  it "sends a guest to login with back_to" do
    get staff_proficient_project_session_path(pps)
    expect(response).to redirect_to(login_path(back_to: staff_proficient_project_session_path(pps)))
  end

  it "sends a regular user to root with an alert" do
    sign_in_as(:regular)
    get staff_proficient_project_session_path(pps)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You cannot access this area.")
  end

  %i[staff admin].each do |role|
    it "lets #{role} view any session, including one they did not approve" do
      sign_in_as(role)
      get staff_proficient_project_session_path(pps)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Proficient Project Session ##{pps.id}")
      expect(response.body).to include(pps.user.email)
    end
  end

  it "404s for an unknown session" do
    sign_in_as(:staff)
    get staff_proficient_project_session_path(0)
    expect(response).to have_http_status(:not_found)
  end

  # WART(D-SP18): the certify_participant route has no controller action: 404 for staff (a dead route).
  it "answers 404 on the dead certify_participant route" do
    sign_in_as(:staff)
    post staff_proficient_project_session_certify_participant_path(pps)
    expect(response).to have_http_status(:not_found)
  end
end
