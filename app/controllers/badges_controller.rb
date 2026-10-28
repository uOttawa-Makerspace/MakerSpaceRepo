# frozen_string_literal: true

class BadgesController < DevelopmentProgramsController
  skip_before_action :grant_access, only: [:show]

  def index
    @pagy, @badge_data = pagy(badge_scope(params[:search]), limit: 20)

    respond_to do |format|
      format.js
      format.html
    end
  end

  def search
    @search_term = params[:search] # Store search term for pagination
    @pagy, @badge_data = pagy(badge_scope(params[:search]), limit: 20)
    render partial: "badges/badge_list", layout: false
  end

  # app/controllers/badges_controller.rb

  def show
    @certification = Certification.find(params[:id])
    @earner = User.find(@certification.user_id)
    @los_en = @certification.training.tokenize_info_en
    @los_fr = @certification.training.tokenize_info_fr
    @skill_colour =
      if @certification.training.skill_id == 1
        "#488b2c"
      elsif @certification.training.skill_id == 2
        "#dc4720"
      else
        "#3f7ed1"
      end
  end

  private

  def badge_scope(search_term = nil)
    certifications = Certification
      .includes(:training, :user, :training_session)
      .joins(:training, :training_session)
      .where(trainings: { has_badge: true })

    # Apply user filter if not admin/staff
    certifications = certifications.where(user: @user) unless @user.admin? || @user.staff?

    # Apply search if present
    if search_term.present?
      search_pattern = "%#{search_term}%"
      certifications = certifications
        .joins(:user)
        .where(
          "trainings.name_en ILIKE :search OR 
           trainings.name_fr ILIKE :search OR 
           users.username ILIKE :search OR 
           users.name ILIKE :search",
          search: search_pattern
        )
    end

    certifications.order(user_id: :asc)
  end

  def only_admin_access
    return if current_user.admin?
    redirect_to development_programs_path
    flash[:alert] = "Only admin members can access this area."
  end
end
