class BadgesController < ApplicationController
  layout 'development_program'
  before_action :only_admin_access, only: [:admin, :new_badge]

  def index
    begin
      if (@user.admin? || @user.staff?)
        @acclaim_data = Badge.order(user_id: :asc).all
      else
        @acclaim_data = @user.badges
      end
    end
  end

  def admin
    @users = User.all
  end

  def new_badge
    # TODO : Try to find a better way to loop through all the orders in the admin.html.erb
    # TODO : Fix the order status (maybe put the statuses in order_items instead ?
    # TODO : Add cancel when the statuses for the order_items is in place

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
        redirect_to badges_path
        flash[:alert] = "An error has occurred when creating the badge, this message might help : "+JSON.parse(response.body)['data']['message']

      elsif response.status == 201
        badge_data =  JSON.parse(response.body)['data']
        Badge.create(:username => user.username, :user_id => user.id, :image_url => badge_data['image_url'], :issued_to => badge_data['issued_to'], :description => badge_data['badge_template']['description'], :badge_id => badge_data['id'])
        Order.update(params['order_id'], :order_status => OrderStatus.find_by(name: "Rewarded"))
        redirect_to admin_badges_path
        flash[:notice] = "The badge has been sent to the user !"

      else
        redirect_to badges_path
        flash[:alert] = "An error has occurred when creating the badge"
      end

    rescue
      redirect_to admin_badges_path
      flash[:alert] = "An error has occurred when creating the badge"
    end

  end

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    end
  end

end
