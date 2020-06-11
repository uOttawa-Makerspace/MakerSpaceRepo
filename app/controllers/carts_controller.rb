class CartsController < DevelopmentProgramsController
  def index
    @order_items = current_order.order_items
  end
end
