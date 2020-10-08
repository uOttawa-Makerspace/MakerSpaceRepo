class Admin::SkillsController < AdminAreaController
  before_action :set_skill, only: %i[edit update destroy]

  def index
    @skills = Skill.all
  end

  def new
    @new_skill = Skill.new
  end

  def edit; end

  def create
    @new_skill = Skill.new(skills_params)
    if @new_skill.save
      flash[:notice] = 'Skill added successfully!'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_skills_path
  end

  def update
    @skill.update(skills_params)
    if @skill.save
      flash[:notice] = 'Skill renamed successfully'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_skills_path
  end

  def destroy
    if @skill.destroy
      flash[:notice] = 'Skill Deleted successfully'
    else
      flash[:alert] = 'An error occured while deleting the skill.'
    end
    redirect_to admin_skills_path
  end

  private

    def skills_params
      params.require(:skill).permit(:name)
    end

    def set_skill
      @skill = Skill.find(params[:id])
    end

end
