class VolunteersController < ApplicationController
  layout 'volunteer'
  before_action :current_user
  before_action :grant_access
  before_action :check_skills
  def index
    @user = current_user
  end

  def emails
    @all_emails = User.where(:role => "volunteer").pluck(:email)
    @active_emails = User.where(:role => "volunteer").joins(:skill).where("skills.active =?", true).pluck(:email)
    @unactive_emails = User.where(:role => "volunteer").joins(:skill).where("skills.active =?", false).pluck(:email)
  end

  private

  def grant_access
    unless current_user.volunteer? || current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end

  def check_skills
    unless current_user.skill
      Skill.create(:user_id => current_user.id)
    end
  end
end
