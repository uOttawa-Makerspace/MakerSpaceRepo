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
      @order.order_items.each do |order_item|
        CcMoney.create_cc_money_from_order(order_item.proficient_project.id, @order.user.id, order_item.total_price.to_i)
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
