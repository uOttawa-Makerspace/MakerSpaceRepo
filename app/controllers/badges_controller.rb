class BadgesController < ApplicationController
  layout 'development_program'
  before_action :only_admin_access, only: [:admin, :certify]

  def index
    begin
      if (@user.admin? || @user.staff?)
        @acclaim_data = Badge.filter_by_attribute(params[:search]).order(user_id: :asc).paginate(:page => params[:page], :per_page => 20).all
      else
        @acclaim_data = @user.badges.paginate(:page => params[:page], :per_page => 20)
      end
    end
  end

  def new_badge
    @badges = Badge.new
  end

  def grant_badge

    begin
      @order = Order.create(subtotal: 0, total: 0, user_id: params["badge"]['user_id'], order_status_id: OrderStatus.find_by(name: "Completed"))
      @order.update(order_status: OrderStatus.find_by(name: "Completed"))
      @order_item = OrderItem.create(unit_price: 0, total_price: 0, quantity: 1, status: "Awarded", order_id: @order.id, proficient_project_id: ProficientProject.find_by_badge_id(params[:badge][:badge_id]).id)

      redirect_to certify_badges_path(user_id: params["badge"][:user_id], order_item_id: @order_item.id, badge_id: params["badge"][:badge_id], coming_from: "grant")

    rescue
      flash[:alert] = "An error has occurred when creating the badge"
      redirect_to new_badge_badges_path
    end

  end

  def admin
    @order_items = OrderItem.completed_order.order(status: :asc).includes(:order => :user).joins(:proficient_project).paginate(:page => params[:page], :per_page => 20)
  end


  def revoke_badge
    begin
      user = User.find(params[:badge][:user_id])
      badge_template_id = user.badges.where(badge_id: params[:badge][:badge_id]).includes(:badge_template).first.badge_template.badge_id
      puts(badge_template_id)
      puts(ProficientProject.where(badge_id: badge_template_id).ids)
      user.order_items.each do |order_item|
        if ProficientProject.where(badge_id: badge_template_id).ids.include? order_item.proficient_project_id
          OrderItem.update(order_item.id, status: "Revoked")
        end
      end
      user.badges.find_by_badge_id(params[:badge][:badge_id]).destroy
      flash[:notice] = "The badge has been revoked to the user"
      redirect_to new_badge_badges_path
    rescue
       flash[:alert] = "An error has occurred when removing the badge"
       redirect_to new_badge_badges_path
    end
  end

  def populate_badge_list
    json_data = User.find(params[:user_id]).badges.map do |badges|
      badges.as_json(include: :badge_template)
    end

    render json: { badges: json_data }
  end

  def certify
    # TODO Repair the flash messages when reloading with rails
    begin
      user = User.find(params['user_id'])
      badge_id = params['badge_id']
      response = Excon.post('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges',
                            :user => Rails.application.secrets.acclaim_api,
                            :password => '',
                            :headers => {"Content-type" => "application/json"},
                            :query => {:recipient_email => user.email, :badge_template_id => badge_id, :issued_to_first_name => user.name.split(" ", 2)[0], :issued_to_last_name => user.name.split(" ", 2)[1], :issued_at => Time.now}
      )

      if response.status == 422
        flash[:alert] = "An error has occurred when creating the badge, this message might help : " + JSON.parse(response.body)['data']['message']

      elsif response.status == 201
        badge_data = JSON.parse(response.body)['data']
        Badge.create(:username => user.username, :user_id => user.id, :image_url => badge_data['image_url'], :issued_to => badge_data['issued_to'], :description => badge_data['badge_template']['description'], :badge_id => badge_data['id'], :badge_template_id => BadgeTemplate.find_by_badge_id(badge_data['badge_template']['id']).id)
        OrderItem.update(params['order_item_id'], :status => "Awarded")
        flash[:notice] = "The badge has been sent to the user !"

      else
        flash[:alert] = "An error has occurred when creating the badge"
      end

    rescue
      flash[:alert] = "An error has occurred when creating the badge"
    ensure
      @order_items = OrderItem.completed_order.order(status: :asc).includes(:order => :user).joins(:proficient_project).paginate(:page => params[:page], :per_page => 20)
      if params[:coming_from] == "grant"
        redirect_to admin_badges_path
      end
    end

  end

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    end
  end

end
