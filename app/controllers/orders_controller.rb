# frozen_string_literal: true

class OrdersController < DevelopmentProgramsController
  before_action :with_development_header
  before_action :check_wallet, only: :create
  before_action :check_permission, only: :destroy

  def index
    completed_status = OrderStatus.find_by(name: "Completed")
    # Listed orders show their stored subtotal (Order#subtotal of a completed order): no per-row
    # pricing. Status, items and projects are loaded with the page.
    user_orders_scope = current_user.orders.where(order_status: completed_status)
                                    .includes(:order_status, order_items: :proficient_project)
                                    .order(created_at: :desc)
    
    @pagy, @orders = pagy(user_orders_scope, limit: 20)

    if current_user.admin?
      @pagy_all, @all_orders = pagy(Order.includes(:user, :order_status, order_items: :proficient_project)
                                         .order(created_at: :desc), page_key: "page_all", limit: 20)
    end
  end

  # The before_action check_wallet is only an early, friendly refusal: Order.checkout! re-decides
  # under the wallet lock (CcMoney.debit_all!), so two checkouts, or a checkout racing a coupon claim,
  # cannot overdraw the wallet.
  def create
    outcome, order, kit_project_ids = Order.checkout!(current_order, current_user)
    if outcome == :invalid_items
      flash[:alert] = INVALID_CART_MESSAGE
      redirect_back(fallback_location: root_path)
      return
    end
    unless %i[completed already_completed].include?(outcome)
      # :invalid or :not_open: nothing was written; the cart (session[:order_id]) is kept
      flash[:alert] = "Something went wrong"
      redirect_back(fallback_location: root_path)
      return
    end

    # :completed, or :already_completed (a concurrent submit of the same cart completed it)
    send_kit_emails(order.user, kit_project_ids)
    session[:order_id] = nil
    flash[:notice] = "Your Order was successfully processed."
    redirect_to orders_path
  rescue CcMoney::InsufficientBalance
    flash[:alert] = "Not enough Cc Points."
    redirect_back(fallback_location: root_path)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotFound,
         ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked, CcMoney::InvalidAmount => e
    # checkout!'s transaction has rolled back: nothing was completed or debited
    Rails.logger.warn("[orders#create] checkout not completed: #{e.class}")
    flash[:alert] = "Something went wrong"
    redirect_back(fallback_location: root_path)
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

  # After the commit: an SMTP failure cannot undo a completed, paid order. Reported; the error class only is logged.
  def send_kit_emails(user, kit_project_ids)
    kit_project_ids.each do |project_id|
      MsrMailer.send_kit_email(user, project_id).deliver_now
    rescue StandardError => e
      Rails.logger.error("[orders#create] kit email NOT sent: user id=#{user.id} proficient_project id=#{project_id} #{e.class}")
      Rails.error.report(e, handled: true, severity: :error, context: { user_id: user.id, proficient_project_id: project_id })
    end
  end

  INVALID_CART_MESSAGE = "An item in your cart can no longer be bought; remove it and try again."

  # Early, friendly refusal (checkout! re-checks under the wallet lock), on the SAME total the
  # charge uses (Order#subtotal of the open cart). A read: no lock, no cache write.
  def check_wallet
    total = current_order.subtotal
    if total.nil?
      flash[:alert] = INVALID_CART_MESSAGE
      redirect_back(fallback_location: root_path)
      return
    end
    return if current_user.get_total_cc >= total

    flash[:alert] = "Not enough Cc Points."
    redirect_back(fallback_location: root_path)
  end

  def check_permission
    return if current_user.admin?
    flash[:alert] = "You can't perform this action"
    redirect_back(fallback_location: root_path)
  end
end
