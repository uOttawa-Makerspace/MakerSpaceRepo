class ProjectRequirementsController < ProficientProjectsController
  before_action :only_admin_access
  before_action :set_proficient_project
  def create
    @required_project = @proficient_project.project_requirements.build(required_project_id: params[:required_project_id])
    if @required_project.save
      flash[:notice] = "Required project added."
    else
      flash[:alert] = "Something went wrong. Try again."
    end
    redirect_to proficient_project_path(@proficient_project.id)
  end

  def destroy

  end

  private

end
