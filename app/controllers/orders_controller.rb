class OrdersController < DevelopmentProgramsController
  before_action :check_wallet, only: :create

  def index
    @orders = current_user.orders.where(order_status: OrderStatus.find_by(name: "Completed")).order("created_at DESC")
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

  private

    def check_wallet
      current_user.update_wallet
      unless current_user.wallet >= current_order.subtotal.to_i
        flash[:alert] = "Not enough Cc Points."
        redirect_to :back
      end
    end
end
