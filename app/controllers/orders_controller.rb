# frozen_string_literal: true

class OrdersController < DevelopmentProgramsController
  before_action :check_wallet, only: :create
  before_action :check_permission, only: :destroy

  def index
    completed_status = OrderStatus.find_by(name: "Completed")
    user_orders_scope = current_user.orders.where(order_status: completed_status).order(created_at: :desc)
    
    @pagy, @orders = pagy(user_orders_scope, limit: 20)

    if current_user.admin?
      @pagy_all, @all_orders = pagy(Order.order(created_at: :desc), page_key: "page_all", limit: 20)
    end
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
        @order.cc_moneys.create(
          proficient_project: order_item.proficient_project,
          user: user,
          cc: cc
        )
        next unless order_item.proficient_project.has_project_kit?
        ProjectKit.create(
          user_id: @order.user_id,
          proficient_project_id: order_item.proficient_project_id,
          delivered: false
        )
        MsrMailer.send_kit_email(
          @order.user,
          order_item.proficient_project_id
        ).deliver_now
      end
      current_user.update_wallet
      session[:order_id] = nil
      flash[:notice] = "Your Order was successfully processed."
      redirect_to orders_path
    else
      flash[:alert] = "Something went wrong"
      redirect_back(fallback_location: root_path)
    end
  end

  def destroy
    @order = Order.find(params[:id])
    @order.destroy
    flash[
      :notice
    ] = "The order was deleted and the CC points returned to the user."
    redirect_to orders_path
  end

  private

  def check_wallet
    current_user.update_wallet
    return if current_user.wallet >= current_order.subtotal.to_i
    flash[:alert] = "Not enough Cc Points."
    redirect_back(fallback_location: root_path)
  end

  def check_permission
    return if current_user.admin?
    flash[:alert] = "You can't perform this action"
    redirect_back(fallback_location: root_path)
  end
end
