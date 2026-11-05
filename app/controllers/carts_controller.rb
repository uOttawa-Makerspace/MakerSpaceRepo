# frozen_string_literal: true

class CartsController < DevelopmentProgramsController
  def index
    @order = current_order
    @order_items = @order.cart_items
  end
end
