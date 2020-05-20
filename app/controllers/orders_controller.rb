class OrdersController < DevelopmentProgramsController
  def index
    @orders = current_user.orders.order("created_at DESC")
  end

  def create
    @order = current_order
    @order.user = current_user
    @order.total = @order.subtotal
    @order.order_status_id = 2
    if @order.save
      session[:order_id] = nil
      flash[:notice] = 'Your Order was successfully processed.'
      redirect_to orders_path
    else
      flash[:alert] = 'Something went wrong'
      redirect_to :back
    end
  end
end
