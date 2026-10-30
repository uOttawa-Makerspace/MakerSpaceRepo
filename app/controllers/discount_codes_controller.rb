# frozen_string_literal: true

# Despite the name this is the CouponCode claim UI: users trade CC points for an
# unclaimed CouponCode. (The Shopify PriceRule/DiscountCode flow was removed in chunk 20a.)
class DiscountCodesController < DevelopmentProgramsController
  before_action :with_development_header
  before_action :check_and_set_price_rule_expiration, only: :create
  before_action :check_user_wallet, only: :create

  def index
    @coupon_codes = CouponCode.where(user_id: current_user)
    @all_discount_codes = CouponCode.all.order(created_at: :desc) if current_user.admin?
  end

  def new
    @price_rules = CouponCode.unclaimed.distinct.pluck(:dollar_cost, :cc_cost)
  end

  # The before_actions are only early, friendly refusals; CouponCode.claim! re-decides both
  # (coupon still unclaimed, enough CC) under locks, so a lost race neither charges nor assigns
  # (D-S33).
  def create
    outcome, = CouponCode.claim!(current_user, params[:dollar_cost])
    case outcome
    when :claimed
      flash[:notice] = "Discount Code created"
      redirect_to discount_codes_path
    when :no_coupon
      flash[:alert] = "This coupon is already claimed"
      redirect_to new_discount_code_path
    else
      flash[:alert] = "Not enough CC points"
      redirect_back(fallback_location: root_path)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveRecord::LockWaitTimeout => e
    # claim!'s transaction has rolled back: nothing was charged or assigned
    Rails.logger.warn("[discount_codes#create] coupon claim not saved: #{e.class}: #{e.message}")
    flash[:alert] = "Discount Code not created properly!"
    redirect_to discount_codes_path
  end

  private

  def check_and_set_price_rule_expiration
    @price_rule =
      CouponCode.unclaimed.find_by(dollar_cost: params[:dollar_cost])
    unless @price_rule
      flash[:alert] = "Can not find coupon for $#{params[:dollar_cost]} off"
      redirect_to new_discount_code_path
    end
    unless @price_rule.user.nil?
      flash[:alert] = "This coupon is already claimed"
      redirect_to new_discount_code_path
    end
  end

  # Read-only early refusal (claim! re-checks under the wallet lock); writes no cache.
  def check_user_wallet
    unless current_user.get_total_cc >= @price_rule.cc_cost.to_i
      flash[:alert] = "Not enough CC points"
      redirect_back(fallback_location: root_path)
    end
  end
end
