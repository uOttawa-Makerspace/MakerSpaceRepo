# frozen_string_literal: true

class OrderItemsController < DevelopmentProgramsController
  # Modals are fragments fetched by the staff-only requests page
  before_action :ensure_staff_modal,
                only: %i[
                  order_item_modal
                  approve_order_item_modal
                  revoke_order_item_modal
                ]

  before_action :ensure_admin_revoke, only: :revoke

  # Every cart change goes through Order#change_items!: it locks the order row (the lock checkout
  # takes) and refuses a cart that is no longer in progress, so an item added, re-quantified or
  # removed during a checkout can never land in (or vanish from) an order already paid for.
  def create
    @order = current_order
    proficient_project =
      ProficientProject.find(params[:order_item][:proficient_project_id])
    if current_user.has_requirements?(proficient_project.training_requirements)
      @order.change_items! do |cart|
        @order = cart
        cart.user = current_user
        @order_item = cart.order_items.new(order_item_params)
        existing_order =
          cart.order_items.where(proficient_project: proficient_project)
        if existing_order.count < 1
          cart.save
          flash[:notice] = "Successfully added item to cart"
        else
          flash[:alert] = "You have already ordered this item"
        end
      end
    else
      @order.user = current_user
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
  rescue *CART_CHANGE_REFUSED => e
    redirect_to carts_path, alert: cart_change_refused_message(e)
  end

  def update
    @order = current_order
    @order.change_items! do |cart|
      @order = cart
      @order_item = cart.order_items.find(params[:id])
      @order_item.update(order_item_params)
      @order_items = cart.order_items
    end
  rescue *CART_CHANGE_REFUSED => e
    # nothing was written: re-render the cart as it really is (the quantity is reverted on screen)
    @refusal_message = cart_change_refused_message(e)
    @order_item = nil
    @order_items = current_order.order_items
    render :update_refused, status: :conflict
  end

  def destroy
    @order = current_order
    @order.change_items! do |cart|
      @order = cart
      @order_item = cart.order_items.find(params[:id])
      @order_item.destroy
      @order_items = cart.order_items
    end
    redirect_to carts_path, notice: "Successfully removed item from cart"
  rescue *CART_CHANGE_REFUSED => e
    redirect_to carts_path, alert: cart_change_refused_message(e)
  end

  CART_CLOSED_MESSAGE = "This cart was just checked out; it can no longer be changed."
  CART_BUSY_MESSAGE = "Your cart is being updated elsewhere; please try again."
  # change_items! refusals; its transaction has rolled back, nothing was written
  CART_CHANGE_REFUSED = [Order::CartClosed, ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked].freeze

  def revoke
    if OrderItem.find(params[:order_item_id]).update(status: "Revoked")
      flash[:notice] = "The badge has been revoked."
    else
      flash[:alert] = "There was an error trying to revoke the badge, please try again later."
    end
    redirect_to admin_index_path
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

  def cart_change_refused_message(error)
    error.is_a?(Order::CartClosed) ? CART_CLOSED_MESSAGE : CART_BUSY_MESSAGE
  end

  def ensure_staff_modal
    head :forbidden unless current_user.staff?
  end

  def ensure_admin_revoke
    head :forbidden unless current_user.admin?
  end

  def order_item_params
    params.require(:order_item).permit(:quantity, :proficient_project_id)
  end
end
