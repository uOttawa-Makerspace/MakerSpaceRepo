class BadgesController < ApplicationController
  layout 'development_program'
  before_action :only_admin_access, only: [:admin, :certify, :new_badge, :grant_badge, :revoke_badge, :reinstante, :update_badge_template, :update_badge_data]

  def index
    if (@user.admin? || @user.staff?)
      @acclaim_data = Badge.filter_by_attribute(params[:search]).order(user_id: :asc).paginate(:page => params[:page], :per_page => 20).all
    else
      @acclaim_data = Badge.filter_by_attribute(params[:search]).where(user: @user).paginate(:page => params[:page], :per_page => 20)
    end
    respond_to do |format|
      format.js
      format.html
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
    admin_variable_setup
  end


  def revoke_badge
    begin
      if params[:badge].present?
        user = User.find(params[:badge][:user_id])
        badge_id = params[:badge][:badge_id]
      else
        user = User.find(params[:user_id])
        badge_id = params[:badge_id]
      end
      badge_template_id = user.badges.where(badge_id: badge_id).includes(:badge_template).first.badge_template.badge_id
      puts(ProficientProject.where(badge_id: badge_template_id).ids)
      response = Excon.put('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges/'+badge_id+"/revoke",
                            :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                            :password => '',
                            :headers => {"Content-type" => "application/json"},
                            :query => {:reason => "Admin revoked badge", :suppress_revoke_notification_email => false}

      )
      if response.status == 200
        user.order_items.each do |order_item|
          if ProficientProject.where(badge_id: badge_template_id).ids.include? order_item.proficient_project_id
            OrderItem.update(order_item.id, status: "Revoked")
          end
        end
        user.badges.find_by_badge_id(badge_id).destroy
        flash[:notice] = "The badge has been revoked to the user"
        if params[:coming_from] == "admin"
          redirect_to admin_badges_path
        else
          redirect_to new_badge_badges_path
        end
      else
        flash[:alert] = "An error has occurred when removing the badge"
        redirect_to new_badge_badges_path
      end
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

  def reinstante
    begin
      if params[:previous_action] = "Revoked"
        OrderItem.update(params['order_item_id'], :status => "In progress")
      elsif params[:previous_action] = "Awarded"
        badge_id = params['badge_id']
        response = Excon.post('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/'+badge_id+"/revoke",
                              :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                              :password => '',
                              :headers => {"Content-type" => "application/json"},
                              :query => {:reason => "Admin revoked badge", :suppress_revoke_notification_email => false}
        )

        if response.status == 200
          OrderItem.update(params['order_item_id'], :status => "In progress")
        else
          flash[:alert] = "An error has occurred while reinstating the badge"
        end
      end

    rescue
      flash[:alert] = "An error has occurred while reinstating the badge"
    ensure
      admin_variable_setup
      redirect_to admin_badges_path
    end

  end


  def certify
    # TODO Repair the flash messages when reloading with rails
    begin
      user = User.find(params['user_id'])
      badge_id = params['badge_id']
      response = Excon.post('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges',
                            :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
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
      admin_variable_setup

      if params[:coming_from] == "grant" or params[:coming_from] == "admin"
        redirect_to admin_badges_path
      end

    end

  end

  def update_badge_templates
    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badge_templates',
                           :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                           :password => '',
                           :headers => {"Content-type" => "application/json"})
      data = JSON.parse(response.body)
      data['data'].each do |badge_template|
        bt = BadgeTemplate.find_or_create_by(badge_id: badge_template['id'])
        bt.update_attributes(badge_description: badge_template['description'], badge_name: badge_template['name'], image_url: badge_template['image_url'])
      end
      flash[:notice] = "Update is now complete !"
    rescue
      flash[:alert] = "Update failed, please try again later"
    ensure
      redirect_to admin_badges_path
    end
  end

  def update_badge_data
    begin
      response = Excon.get('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/high_volume_issued_badge_search',
                           :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                           :password => '',
                           :headers => {"Content-type" => "application/json"}
      )
      data = JSON.parse(response.body)

      data['data'].each do |badges|

        if User.where(email: badges['recipient_email']).present?
          user = User.where(email: badges['recipient_email']).first
          if user.badges.where(badge_id: badges['id']).present? == false
            values = {user_id: user.id, username: user.username, image_url: badges['badge_template']['image']['url'], description: badges['badge_template']['description'], issued_to: badges['issued_to'], badge_id: badges['id'], badge_url: badges['badge_url'], :badge_template_id => BadgeTemplate.find_by_badge_id(badges['badge_template']['id'])}
            Badge.create(values)
          elsif user.badges.where(badge_id: badges['id']).present? and user.badges.where(badge_url: badges['badge_url']).present? == false and badges['badge_url'] != ""
            Badge.update(user.badges.where(badge_id: badges['id']), :badge_url => badges['badge_url'])
          elsif user.badges.where(badge_id: badges['id']).present? and user.badges.where(badge_url: badges['badge_url']).present? and user.badges.where(badge_template_id: BadgeTemplate.find_by_badge_id(badges['badge_template']['id'])).present? == false
            Badge.update(user.badges.where(badge_id: badges['id']), :badge_template_id => BadgeTemplate.find_by_badge_id(badges['badge_template']['id']).id)
          end
        end
      end
      flash[:notice] = "Update is now complete !"
    rescue
      flash[:alert] = "Update failed, please try again later"
    ensure
      redirect_to admin_badges_path
    end
  end

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    end
  end

  def admin_variable_setup
    order_items = OrderItem.completed_order.order(updated_at: :desc).includes(:order => :user).joins(:proficient_project).where.not(:proficient_projects => {badge_id: ""})
    @order_items = order_items.where(status: "In progress").paginate(:page => params[:page], :per_page => 20)
    @order_items_done = order_items.where.not(status: "In progress").paginate(:page => params[:page], :per_page => 20)
  end
end
