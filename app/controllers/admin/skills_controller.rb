class Admin::SkillsController < AdminAreaController
  before_action :set_skill, only: %i[edit update destroy]

  def index
    @skills = Skill.all
  end

  def new
    @new_skill = Skill.new
  end

  def edit
  end

  def create
    @new_skill = Skill.new(skills_params)
    if @new_skill.save
      flash[:notice] = t("admin_area.skills.flash.created")
    else
      flash[:alert] = t("admin_area.input_invalid")
    end
    redirect_to admin_skills_path
  end

  def update
    @skill.update(name: params[:skill][:name])
    if @skill.save
      flash[:notice] = t("admin_area.skills.flash.renamed")
    else
      flash[:alert] = t("admin_area.input_invalid")
    end
    redirect_to admin_skills_path
  end

  def destroy
    if @skill.destroy
      flash[:notice] = t("admin_area.skills.flash.deleted")
    else
      flash[:alert] = t("admin_area.skills.flash.not_deleted")
    end
    redirect_to admin_skills_path
  end

  private

  def skills_params
    params.permit(:name, :skill)
  end

  def set_skill
    @skill = Skill.find(params[:id])
  end
end
