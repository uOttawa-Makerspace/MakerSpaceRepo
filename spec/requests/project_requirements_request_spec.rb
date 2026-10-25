# frozen_string_literal: true

require "rails_helper"

# Chunk 16: ProjectRequirementsController (< ProficientProjectsController).
# Inherited gates: signed_in, then only_admin_access (non-admin -> proficient
# projects index, silently). `create` takes the target project from params[:id]
# (a hidden field in the show page form), the prerequisite from
# params[:required_project_id].
RSpec.describe "Project requirements (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let!(:project) { create(:proficient_project, title: "Main project") }
  let!(:prereq) { create(:proficient_project, title: "Prereq project") }

  def add(id: project.id, required: prereq.id)
    post project_requirements_path, params: { id: id, required_project_id: required }
  end

  it "sends a guest to login and creates nothing" do
    expect { add }.not_to change(ProjectRequirement, :count)
    expect(response.location).to include("/login")
  end

  %i[regular staff].each do |role|
    it "#{role} is silently bounced to the projects index; nothing created or removed" do
      req = ProjectRequirement.create!(proficient_project: project, required_project: prereq)
      content_sign_in_as(role)
      expect { add(required: create(:proficient_project).id) }.not_to change(ProjectRequirement, :count)
      expect(response).to redirect_to(proficient_projects_path)
      expect { delete project_requirement_path(req) }.not_to change(ProjectRequirement, :count)
      expect(response).to redirect_to(proficient_projects_path)
    end
  end

  describe "as admin" do
    before { content_sign_in_as(:admin) }

    it "adds a prerequisite and redirects to the project" do
      expect { add }.to change(ProjectRequirement, :count).by(1)
      expect(response).to redirect_to(proficient_project_path(project.id))
      expect(flash[:notice]).to eq("Required project added.")
      expect(project.reload.required_projects).to eq([prereq])
      expect(prereq.reload.inverse_required_projects).to eq([project])
    end

    it "a duplicate pair alerts instead of persisting" do
      add
      expect { add }.not_to change(ProjectRequirement, :count)
      expect(flash[:alert]).to eq("Something went wrong. Try again.")
    end

    it "allows a project to require itself and circular requirements (no guard) (D-C48)" do
      expect { add(required: project.id) }.to change(ProjectRequirement, :count).by(1)
      # WART(D-C48): no self/cycle validation (the show page only hides them from its picker)
      add(id: prereq.id, required: project.id)
      add(id: project.id, required: prereq.id)
      expect(ProjectRequirement.count).to eq(3)
    end

    it "persists a blank prerequisite id (nil required_project) (D-C48)" do
      expect { add(required: "") }.to change(ProjectRequirement, :count).by(1)
      expect(ProjectRequirement.last.required_project_id).to be_nil
    end

    it "404s when the target project is unknown or the id param is missing" do
      add(id: 0)
      expect(response).to have_http_status(:not_found)
      post project_requirements_path, params: { required_project_id: prereq.id }
      expect(response).to have_http_status(:not_found)
    end

    it "removes a requirement and redirects to its project" do
      req = ProjectRequirement.create!(proficient_project: project, required_project: prereq)
      expect { delete project_requirement_path(req) }.to change(ProjectRequirement, :count).by(-1)
      expect(response).to redirect_to(proficient_project_path(project.id))
      expect(flash[:notice]).to eq("Removed Project Requirement")
      expect(ProficientProject.exists?(prereq.id)).to be(true)
    end

    it "destroy of an unknown requirement 404s" do
      delete project_requirement_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
