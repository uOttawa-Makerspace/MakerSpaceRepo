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

  def create
    cc_money_payment =
      CcMoney.make_new_payment(current_user, @price_rule.cc_cost)
    if cc_money_payment.present? && cc_money_payment.save
      if @price_rule.update(user: current_user)
        flash[:notice] = "Discount Code created"
      else
        cc_money_payment.destroy
        flash[:alert] = "Discount Code not created properly!"
      end
    else
      flash[:alert] = "Payment not processed"
    end
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

  def check_user_wallet
    current_user.update_wallet
    unless current_user.wallet >= @price_rule.cc_cost
      flash[:alert] = "Not enough CC points"
      redirect_back(fallback_location: root_path)
    end
  end
end
