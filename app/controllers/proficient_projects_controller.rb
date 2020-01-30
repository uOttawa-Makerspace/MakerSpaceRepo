class ProficientProjectsController < DevelopmentProgramsController
  before_action :grant_access_to_project, only: [:show]

  def index
  end

  def new
    @proficient_project = ProficientProject.new
  end

  def show
  end

  def create
  end

  private

  def grant_access_to_project
    unless current_user.dev_program? || current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end

end
