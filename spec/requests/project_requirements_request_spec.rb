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
      expect(flash[:alert]).to eq("The required project was not added. Proficient project This project is already a pre-requisite")
    end

    it "refuses a project that requires itself" do
      expect { add(required: project.id) }.not_to change(ProjectRequirement, :count)
      expect(flash[:alert]).to start_with("The required project was not added.")
    end

    it "refuses a requirement that would close a circle" do
      third = create(:proficient_project, title: "Third project")
      add(id: project.id, required: prereq.id)
      add(id: prereq.id, required: third.id)
      expect { add(id: third.id, required: project.id) }.not_to change(ProjectRequirement, :count)
      expect { add(id: prereq.id, required: project.id) }.not_to change(ProjectRequirement, :count)
      expect(flash[:alert]).to start_with("The required project was not added.")
    end

    it "refuses a blank or unknown prerequisite id" do
      expect { add(required: "") }.not_to change(ProjectRequirement, :count)
      expect { add(required: 0) }.not_to change(ProjectRequirement, :count)
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
