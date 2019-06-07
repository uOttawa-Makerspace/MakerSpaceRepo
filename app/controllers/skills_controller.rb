class SkillsController < ApplicationController
  def edit
    @skills = current_user.skill
  end
end
