# frozen_string_literal: true

class ProjectRequirementsController < ProficientProjectsController
  before_action :only_admin_access
  before_action :set_proficient_project, except: :destroy
  def create
    project_requirement = @proficient_project.project_requirements.build(required_project_id: params[:required_project_id])
    if project_requirement.save
      flash[:notice] = 'Required project added.'
    else
      flash[:alert] = 'Something went wrong. Try again.'
    end
    redirect_to proficient_project_path(@proficient_project.id)
  end

  def destroy
    project_requirement = ProjectRequirement.find(params[:id])
    proficient_project = project_requirement.proficient_project
    project_requirement.destroy
    flash[:notice] = 'Removed Project Requirement'
    redirect_to proficient_project_path(proficient_project.id)
  end
end
