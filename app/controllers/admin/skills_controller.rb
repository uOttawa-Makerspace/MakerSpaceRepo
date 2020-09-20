class Admin::SkillsController < AdminAreaController

  def index
    @skills = Skill.all
  end

  def new
    @new_skill = Skill.new
  end

  def edit
    @skill = Skill.find(params[:id])
  end

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
    @changed_skill = Skill.find(params[:id])
    @changed_skill.update(skills_params)
    if @changed_skill.save
      flash[:notice] = 'Skill renamed successfully'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_skills_path
  end

  def destroy
    if Training.where(skills_id: params[:id]).present?
      flash[:alert] = 'The skill is used by trainings, please unlink all trainings from the skill.'
    else
      @skill = Skill.find(params[:id])
      if @skill.destroy
        flash[:notice] = 'Skill Deleted successfully'
      else
        flash[:alert] = 'An error occured while deleting the skill.'
      end
    end
    redirect_to admin_skills_path
  end

  private

  def skills_params
    params.require(:skill).permit(:name)
  end

end
