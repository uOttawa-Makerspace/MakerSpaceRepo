# frozen_string_literal: true

class BadgesController < DevelopmentProgramsController
  before_action :set_orders, only: [:admin]
  skip_before_action :grant_access, only: [:show]

  def index
    @order_items =
      @user.order_items.completed_order.in_progress.joins(
        proficient_project: :badge_template
      )
    
    @badge_data = fetch_badge_data(params[:search])
    
    respond_to do |format|
      format.js
      format.html
    end
  end

  def search
    @badge_data = fetch_badge_data(params[:search])
    @search_term = params[:search] # Store search term for pagination
    render partial: 'badges/badge_list', layout: false
  end

  def show
    @certification = Certification.includes(:training).find(params[:id])
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

  def fetch_badge_data(search_term = nil)
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

    certifications
      .order(user_id: :asc)
      .paginate(page: params[:page], per_page: 20)
  end

  def only_admin_access
    return if current_user.admin?
    redirect_to development_programs_path
    flash[:alert] = "Only admin members can access this area."
  end

  def set_orders
    statuses = ["In progress", "Waiting for approval"]
    order_items =
      OrderItem
        .completed_order
        .order(updated_at: :desc)
        .includes(order: :user)
        .joins(proficient_project: :badge_template)
    @order_items =
      order_items.where(status: statuses).paginate(
        page: params[:page],
        per_page: 20
      )
    @order_items_done =
      order_items
        .where.not(status: statuses)
        .paginate(page: params[:page], per_page: 20)
  end
end