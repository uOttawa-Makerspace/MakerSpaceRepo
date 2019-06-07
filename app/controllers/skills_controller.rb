class SkillsController < ApplicationController
  before_action :current_user
  before_action :signed_in?
  layout "setting"

  def edit
    @skills = Skill.find(params[:id])
  end

  def update
    skill = Skill.find(params[:id])
    if skill.update(skill_params)
      flash[:notice] = "Skills updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to edit_skill_path
  end

  private

  def skill_params
    params.require(:skill).permit(:printing, :laser_cutting, :arduino, :virtual_reality, :embroidery)
  end

end
