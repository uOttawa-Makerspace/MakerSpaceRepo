# frozen_string_literal: true

class OrdersController < DevelopmentProgramsController
  before_action :with_development_header
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

  # The before_action check_wallet is only an early, friendly refusal: Order.checkout! re-decides
  # under the wallet lock (CcMoney.debit!), so two checkouts, or a checkout racing a coupon claim,
  # cannot overdraw the wallet (D-S42).
  def create
    outcome, order, kit_project_ids = Order.checkout!(current_order, current_user)
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

  # After the commit: an SMTP failure cannot undo a completed, paid order (it used to raise mid-loop,
  # a 500 with the order half-debited). Reported; the error class only is logged.
  def send_kit_emails(user, kit_project_ids)
    kit_project_ids.each do |project_id|
      MsrMailer.send_kit_email(user, project_id).deliver_now
    rescue StandardError => e
      Rails.logger.error("[orders#create] kit email NOT sent: user id=#{user.id} proficient_project id=#{project_id} #{e.class}")
      Rails.error.report(e, handled: true, severity: :error, context: { user_id: user.id, proficient_project_id: project_id })
    end
  end

  # Early, friendly refusal (checkout! re-checks under the wallet lock). Only a refusal refreshes
  # the cached wallet (update_wallet, read under the wallet lock); a passing check writes nothing.
  def check_wallet
    return if current_user.get_total_cc >= current_order.subtotal.to_i

    current_user.update_wallet
    flash[:alert] = "Not enough Cc Points."
    redirect_back(fallback_location: root_path)
  end

  def check_permission
    return if current_user.admin?
    flash[:alert] = "You can't perform this action"
    redirect_back(fallback_location: root_path)
  end
end
