class OrdersController < DevelopmentProgramsController
  before_action :check_wallet, only: :create
  before_action :check_permission, only: :destroy

  def index
    @orders = current_user.orders.where(order_status: OrderStatus.find_by(name: "Completed")).order("created_at DESC")
    @all_orders = Order.all.order("created_at DESC") if current_user.admin?
  end

  def create
    @order = current_order
    @order.user = current_user
    @order.total = @order.subtotal
    @order.order_status = OrderStatus.find_by(name: "Completed")
    if @order.save
      user = @order.user
      @order.order_items.each do |order_item|
        cc = order_item.total_price.to_i
        cc *= -1 if cc >= 0
        @order.cc_moneys.create(proficient_project: order_item.proficient_project, user: user, cc: cc)
      end
      current_user.update_wallet
      session[:order_id] = nil
      flash[:notice] = 'Your Order was successfully processed.'
      redirect_to orders_path
    else
      flash[:alert] = 'Something went wrong'
      redirect_to :back
    end
  end

  def destroy
    @order = Order.find(params[:id])
    user = User.find(@order.user_id)
    @order.order_items.where(status: "Awarded").each do |order_item|
      badge_id = user.badges.joins(:badge_template).where(badge_templates: {badge_id: ProficientProject.find(order_item.proficient_project_id).badge_id}).first.badge_id
      begin
        response = Excon.put('https://api.youracclaim.com/v1/organizations/ca99f878-7088-404c-bce6-4e3c6e719bfa/badges/' + badge_id + "/revoke",
                             :user => Rails.application.secrets.acclaim_api || ENV.fetch('acclaim_api'),
                             :password => '',
                             :headers => {"Content-type" => "application/json"},
                             :query => {:reason => "Admin revoked badge", :suppress_revoke_notification_email => false}

        )
        if response.status == 200
          Badge.find_by_badge_id(badge_id).destroy
        else
          flash[:alert] = "An error occurred while trying to delete the order."
          redirect_to orders_path
        end
      end
      @order.destroy
      flash[:notice] = "The order was deleted and the CC points returned to the user."
      redirect_to orders_path
    end
  end

  private

  def check_wallet
    current_user.update_wallet
    unless current_user.wallet >= current_order.subtotal.to_i
      flash[:alert] = "Not enough Cc Points."
      redirect_to :back
    end
  end

  def check_permission
    unless current_user.admin?
      flash[:alert] = "You can't perform this action"
      redirect_to :back
    end

  end
end
