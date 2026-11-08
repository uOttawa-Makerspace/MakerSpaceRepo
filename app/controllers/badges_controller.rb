# frozen_string_literal: true

class BadgesController < DevelopmentProgramsController
  skip_before_action :grant_access, only: [:show]

  # The badge page is public, so each visitor's address is limited to a pace that
  # viewing and sharing badges never reaches. Signed-in staff and admins are exempt.
  rate_limit to: 30, within: 1.minute, only: :show, name: "show-minute", if: -> { throttled_viewer? },
             by: -> { request.remote_ip }, with: -> { badge_throttled }
  rate_limit to: 300, within: 1.hour, only: :show, name: "show-hour", if: -> { throttled_viewer? },
             by: -> { request.remote_ip }, with: -> { badge_throttled }

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
    @certification = Certification.find_for_badge_page!(params[:id])
    @earner = @certification.user
    raise ActiveRecord::RecordNotFound if @earner.nil?
    # A deleted account's badge is visible to admins only.
    raise ActiveRecord::RecordNotFound if @earner.deleted? && !current_user&.admin?
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

  def throttled_viewer?
    !current_user&.staff?
  end

  def badge_throttled
    render plain: "Too many requests, please try again later.", status: :too_many_requests
  end

  def badge_scope(search_term = nil)
    certifications = Certification
      .includes(:training, :user, :training_session)
      .joins(:training, :training_session, :user)
      .where(trainings: { has_badge: true })

    # A deleted earner's badge is shown to admins only (see #show)
    certifications = certifications.where(users: { deleted: false }) unless @user.admin?

    # Apply user filter if not admin/staff
    certifications = certifications.where(user: @user) unless @user.admin? || @user.staff?

    # Apply search if present
    if search_term.present?
      search_pattern = "%#{search_term}%"
      certifications = certifications
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
end
