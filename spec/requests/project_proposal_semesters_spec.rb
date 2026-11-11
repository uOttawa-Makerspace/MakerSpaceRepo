# frozen_string_literal: true

require "rails_helper"

# Setting and clearing the semester a project proposal is active for. Only admins can do either.
RSpec.describe "Project proposal semester", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:proposal) { create(:project_proposal, :approved, user: owner, season: :fall, year: 2024) }

  def semester
    proposal.reload.attributes.values_at("season", "year")
  end

  describe "setting it through the proposal update" do
    it "lets an admin change the semester" do
      content_sign_in_as(:admin)
      patch project_proposal_path(proposal), params: { project_proposal: { season: "winter", year: 2025 } }
      expect(semester).to eq(["winter", 2025])
    end

    it "ignores the semester sent by the owner" do
      content_login!(owner)
      patch project_proposal_path(proposal), params: { project_proposal: { season: "winter", year: 2025 } }
      expect(semester).to eq(["fall", 2024])
    end

    it "refuses a season without a year and keeps the semester" do
      content_sign_in_as(:admin)
      patch project_proposal_path(proposal), params: { project_proposal: { season: "winter", year: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(semester).to eq(["fall", 2024])
    end
  end

  describe "DELETE /project_proposals/:id/semester" do
    it "lets an admin clear the semester" do
      content_sign_in_as(:admin)
      delete project_proposal_semester_path(proposal)
      expect(response).to redirect_to(project_proposal_path(proposal))
      expect(flash[:notice]).to eq("The semester was cleared.")
      expect(semester).to eq([nil, nil])
    end

    it "leaves the rest of the proposal as it was" do
      content_sign_in_as(:admin)
      expect { delete project_proposal_semester_path(proposal) }
        .not_to(change { proposal.reload.attributes.except("season", "year", "updated_at", "slug") })
    end

    it "says so when there was no semester" do
      proposal.update_columns(season: nil, year: nil)
      content_sign_in_as(:admin)
      delete project_proposal_semester_path(proposal)
      expect(response).to redirect_to(project_proposal_path(proposal))
      expect(semester).to eq([nil, nil])
    end

    it "clears a legacy proposal that has only a season" do
      proposal.update_columns(year: nil)
      content_sign_in_as(:admin)
      delete project_proposal_semester_path(proposal)
      expect(semester).to eq([nil, nil])
    end

    %i[regular staff].each do |role|
      it "refuses a #{role} and keeps the semester" do
        content_sign_in_as(role)
        delete project_proposal_semester_path(proposal)
        expect(response).to redirect_to("/")
        expect(semester).to eq(["fall", 2024])
      end
    end

    it "refuses the owner" do
      content_login!(owner)
      delete project_proposal_semester_path(proposal)
      expect(semester).to eq(["fall", 2024])
    end

    it "sends a guest to sign in and keeps the semester" do
      delete project_proposal_semester_path(proposal)
      expect(response).to have_http_status(:redirect)
      expect(semester).to eq(["fall", 2024])
    end
  end

  describe "the proposal page" do
    it "offers Clear semester to an admin only when a semester is set" do
      content_sign_in_as(:admin)
      get project_proposal_path(proposal)
      expect(response.body).to include("Clear semester", "Clear the active semester of this project proposal?")
      proposal.update_columns(season: nil, year: nil)
      get project_proposal_path(proposal)
      expect(response.body).not_to include("Clear semester")
    end

    it "does not offer it to the owner" do
      content_login!(owner)
      get project_proposal_path(proposal)
      expect(response.body).not_to include("Clear semester")
    end
  end
end
