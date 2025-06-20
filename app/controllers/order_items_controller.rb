# frozen_string_literal: true

class OrderItemsController < DevelopmentProgramsController
  def create
    @order = current_order
    @order.user = current_user
    proficient_project =
      ProficientProject.find(params[:order_item][:proficient_project_id])
    if @order.user.has_required_trainings?(proficient_project.training_requirements, proficient_project)
      begin
        @order_item = @order.order_items.new(order_item_params)
        existing_order =
          @order.order_items.where(proficient_project: proficient_project)
        if existing_order.count < 1
          @order.save
          flash[:notice] = "Successfully added item to cart"
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

    redirect_to carts_path
  end

  def update
    @order = current_order
    @order_item = @order.order_items.find(params[:id])
    @order_item.update(order_item_params)
    @order_items = @order.order_items
  end

  def destroy
    @order = current_order
    @order_item = @order.order_items.find(params[:order_item_id])
    @order_item.destroy
    @order_items = @order.order_items
    redirect_to carts_path, notice: "Successfully removed item from cart"
    
  end

  def revoke
    if OrderItem.find(params[:order_item_id]).update(status: "Revoked")
      flash[:notice] = "The badge has been revoked."
    else
      flash[
        :alert
      ] = "There was an error trying to revoke the badge, please try again later."
    end
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
    @order_items_done =Revoked
      order_items
        .where.not(status: "In progress")
        .paginate(page: params[:page], per_page: 20)
    redirect_to admin_badges_path
  end

  def order_item_modal
    @order_item = OrderItem.find(params[:order_item_id])
    render layout: false
  end

  def approve_order_item_modal
    @order_item = OrderItem.find(params[:order_item_id])
    render layout: false
  end

  def revoke_order_item_modal
    @order_item = OrderItem.find(params[:order_item_id])
    render layout: false
  end

  private

  def order_item_params
    params.require(:order_item).permit(:quantity, :proficient_project_id)
  end
end
