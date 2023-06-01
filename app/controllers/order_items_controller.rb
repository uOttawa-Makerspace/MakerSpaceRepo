# frozen_string_literal: true

class OrderItemsController < DevelopmentProgramsController
  def create
    create_successful = false
    @order = current_order
    @order.user = current_user
    proficient_project =
      ProficientProject.find(params[:order_item][:proficient_project_id])
    if @order.user.has_required_badges?(proficient_project.badge_requirements)
      begin
        @order_item = @order.order_items.new(order_item_params)
        existing_order =
          @order.order_items.where(proficient_project: proficient_project)
        if existing_order.count < 1
          @order.save
          flash[:notice] = "Successfully added item to cart"
          create_successful = true
        else
          flash[:alert] = "You have already ordered this item"
        end
      end
    else
      flash[:alert] = "You do not have the required badges to do this project"
    end
    # TODO: update when implementing coupons
    # if existing_order.count >= 1
    #  existing_order.last.update_column(:quantity, existing_order.last.quantity + params[:order_item][:quantity].to_i)
    # else
    #  @order.save
    # end
    session[:order_id] = @order.id

    if create_successful
      redirect_to carts_path
    else
      redirect_to proficient_projects_path
    end
  end

  def update
    @order = current_order
    @order_item = @order.order_items.find(params[:id])
    @order_item.update(order_item_params)
    @order_items = @order.order_items
  end

  def destroy
    @order = current_order
    @order_item = @order.order_items.find(params[:id])
    @order_item.destroy
    @order_items = @order.order_items
  end

  def revoke
    OrderItem.find(params[:order_item_id]).update(status: "Revoked")
    order_items =
      OrderItem
        .completed_order
        .order(updated_at: :desc)
        .includes(order: :user)
        .joins(proficient_project: :badge_template)
    @order_items =
      order_items.where(status: "In progress").paginate(
        page: params[:page],
        per_page: 20
      )
    @order_items_done =
      order_items
        .where.not(status: "In progress")
        .paginate(page: params[:page], per_page: 20)
  end

  def order_item_modal
    @order_item = OrderItem.find(params[:order_item_id])
    render layout: false
  end

  private

  def order_item_params
    params.require(:order_item).permit(:quantity, :proficient_project_id)
  end
end
