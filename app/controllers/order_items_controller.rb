class OrderItemsController < DevelopmentProgramsController
  def create
    @order = current_order
    @order.user = current_user
    @order_item = @order.order_items.new(order_item_params)
    existing_order = @order.order_items.where(proficient_project_id: params[:order_item][:proficient_project_id])
    unless existing_order.count >= 1
      @order.save
    end
    # TODO update when implementing coupons
    #if existing_order.count >= 1
    #  existing_order.last.update_column(:quantity, existing_order.last.quantity + params[:order_item][:quantity].to_i)
    #else
    #  @order.save
    #end
    session[:order_id] = @order.id
  end

  def update
    @order = current_order
    @order_item = @order.order_items.find(params[:id])
    @order_item.update_attributes(order_item_params)
    @order_items = @order.order_items
  end

  def destroy
    @order = current_order
    @order_item = @order.order_items.find(params[:id])
    @order_item.destroy
    @order_items = @order.order_items
  end

  def cancel
    OrderItem.find(params[:order_item_id]).update(status: "Revoked")
    redirect_to admin_badges_path
  end

  private

    def order_item_params
      params.require(:order_item).permit(:quantity, :proficient_project_id)
    end
end
