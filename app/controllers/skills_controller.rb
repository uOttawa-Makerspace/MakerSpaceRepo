class SkillsController < ApplicationController
  before_action :current_user
  before_action :signed_in?
  layout "setting"

  def edit
    @skills = Skill.find(params[:id])
  end

  def update

  end

end
