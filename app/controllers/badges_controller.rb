class BadgesController < DevelopmentProgramsController
  before_action :only_admin_access, only: [:admin, :certify, :new_badge, :grant_badge, :revoke_badge, :reinstate, :update_badge_templates, :update_badge_data]
  after_action :set_orders, only: [:reinstate]
  before_action :set_orders, only: [:admin]

  include BadgesHelper

  def index
    @order_items = @user.order_items.completed_order.in_progress.joins(proficient_project: :badge_template)
    if (@user.admin? || @user.staff?)
      @acclaim_data = Badge.joins(:badge_template).filter_by_attribute(params[:search]).order(user_id: :asc).paginate(:page => params[:page], :per_page => 20).all
    else
      @acclaim_data = Badge.joins(:badge_template).filter_by_attribute(params[:search]).where(user: @user).paginate(:page => params[:page], :per_page => 20)
    end
    respond_to do |format|
      format.js
      format.html
    end

  end

  def new_badge
    @badges = Badge.new
    @all_users = User.all.pluck(:name, :id)
    @users_with_badges = User.joins(:badges).uniq.all.pluck(:name, :id)
    @badge_templates = BadgeTemplate.joins(:proficient_projects).pluck(:badge_name, :id)
  end

  def grant_badge
    begin
      badge = Badge.find_by(badge_params)
      if badge.nil?
        badge_template = BadgeTemplate.find_by_id(params["badge"]['badge_template_id'])
        user_id = params["badge"]['user_id']
        order_status = OrderStatus.find_by(name: "Completed")
        order = Order.create(subtotal: 0, total: 0, user_id: user_id)
        order.update_attributes(order_status_id: order_status.id)
        order_item = OrderItem.create(unit_price: 0, total_price: 0, quantity: 1, status: "Awarded", order: order, proficient_project: badge_template.proficient_projects.last)
        redirect_to certify_badges_path(user_id: user_id, order_item_id: order_item.id, coming_from: "grant")
      else
        flash[:alert] = "The user already has the badge."
        redirect_to new_badge_badges_path
      end
    rescue StandardError => e
      flash[:alert] = "An error has occurred when granting the badge: #{e}"
      redirect_to new_badge_badges_path
    end
  end

  def admin
  end

  def revoke_badge
    begin
      if params[:badge].present?
        badge = Badge.find_by_acclaim_badge_id(params[:badge][:acclaim_badge_id])
        order_item = badge.user.order_items.includes(:proficient_project).where(proficient_projects: {badge_template_id: badge.badge_template_id}).last
      else
        order_item = OrderItem.find(params['order_item_id'])
        badge_template = order_item.proficient_project.badge_template
        user = order_item.order.user
        badge = user.badges.where(badge_template: badge_template).last
      end
      response = badge.acclaim_api_revoke_badge
      if response.status == 200
        order_item.update_attributes(status: "Revoked")
        badge.destroy
        flash[:notice] = "The badge has been revoked"
      else
        flash[:alert] = "An error has occurred when removing the badge: " + JSON.parse(response.body)['data']['message']
      end
    rescue StandardError => e
      flash[:alert] = "An error has occurred when removing the badge: #{e}"
    ensure
      redirect_to :back
    end
  end

  def reinstate
    begin
      order_item = OrderItem.find(params['order_item_id'])
      if order_item.status == "Awarded"
        # TODO: Fix this query when we have a better relation with order_item and badges
        badge = order_item.order.user.badges.where(badge_template: order_item.proficient_project.badge_template).last
        badge.acclaim_api_delete_badge
        badge.destroy
      end
      order_item.update_attributes(:status => "In progress")
      flash[:notice] = "Badge Restored"
    rescue StandardError => e
      flash[:alert] = "An error has occurred while reinstating the badge: #{e}"
    ensure
      redirect_to admin_badges_path
    end
  end


  def certify
    # TODO Repair the flash messages when reloading with rails
    begin
      order_item = OrderItem.find(params['order_item_id'])
      badge_template = order_item.proficient_project.badge_template
      user = order_item.order.user
      response = Badge.acclaim_api_create_badge(user, badge_template.acclaim_template_id)
      if response.status == 201
        badge_data = JSON.parse(response.body)['data']
        Badge.create(:user_id => user.id,
                     :issued_to => user.name,
                     :acclaim_badge_id => badge_data['id'],
                     :badge_template_id => badge_template.id)
        order_item.update_attributes(:status => "Awarded")
        flash[:notice] = "The badge has been sent to the user !"
      else
        flash[:alert] = "An error has occurred when creating the badge, this message might help : " + JSON.parse(response.body)['data']['message']
      end
    rescue StandardError => e
      flash[:alert] = "An error has occurred when creating the badge: #{e}"
    ensure
      set_orders
      if params[:coming_from] == "grant"
        redirect_to new_badge_badges_path
      else
        respond_to do |format|
          format.js
        end
      end
    end
  end

  def populate_badge_list
    json_data = User.find(params[:user_id]).badges.map do |badges|
      badges.as_json(include: :badge_template)
    end

    render json: { badges: json_data }
  end

  def populate_grant_users
    json_data = User.where("LOWER(name) like LOWER(?)", "%#{params[:search]}%").map do |users|
      users.as_json
    end

    render json: { users: json_data }
  end

  def populate_revoke_users
    json_data = User.joins(:badges).uniq.where("LOWER(name) like LOWER(?)", "%#{params[:search]}%").map do |users|
      users.as_json
    end
    render json: { users: json_data }
  end

  def update_badge_data
    update_badge_data_helper
    redirect_to admin_badges_path
  end

  def update_badge_templates
    update_badge_templates_helper
    redirect_to admin_badges_path
  end

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    end
  end

  private

    def set_orders
      order_items = OrderItem.completed_order.order(updated_at: :desc).includes(:order => :user).joins(proficient_project: :badge_template)
      @order_items = order_items.where(status: "In progress").paginate(:page => params[:page], :per_page => 20)
      @order_items_done = order_items.where.not(status: "In progress").paginate(:page => params[:page], :per_page => 20)
    end

    def badge_params
      params.require(:badge).permit(:user_id, :badge_template_id)
    end
end
