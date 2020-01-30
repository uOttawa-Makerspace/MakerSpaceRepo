class ProficientProjectsController < DevelopmentProgramsController
  before_action :grant_access_to_project, only: [:show]
  before_action :only_staff_access, only: [:new, :create]

  def index
  end

  def new
    @proficient_project = ProficientProject.new
  end

  def show
  end

  def create
    proficient_project = ProficientProject.new(proficient_project_params)
    if proficient_project.save
      flash[:notice] = "Proficient Project successfully created."
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to new_proficient_project_path
  end

  private

  def grant_access_to_project
    unless current_user.dev_program? || current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end

  def only_staff_access
    unless current_user.staff?
      redirect_to development_programs_path
      flash[:alert] = "Only staff members can access this area."
    end
  end

  def proficient_project_params
    params.require(:proficient_project).permit(:title, :description)
  end

end
