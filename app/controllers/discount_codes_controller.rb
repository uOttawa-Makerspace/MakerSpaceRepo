class DiscountCodesController < DevelopmentProgramsController
  before_action :set_price_rule, only: :create
  before_action :check_user_wallet, only: :create


  def index
    user_discount_codes = current_user.discount_codes
    @discount_codes = user_discount_codes.not_used.includes(:price_rule).order(:created_at => :desc)
    @expired_codes = user_discount_codes.used_code.includes(:price_rule).count
    @all_discount_codes = DiscountCode.includes(:price_rule).order(:created_at => :desc) if current_user.admin?
  end

  def new
    @price_rules = PriceRule.all
  end

  def create
    cc_money_payment = CcMoney.make_new_payment(current_user, @price_rule.cc)
    if cc_money_payment.present?
      @discount_code = current_user.discount_codes.new
      @discount_code.code = DiscountCode.generate_code
      @discount_code.price_rule = @price_rule
      shopify_discount_code = @discount_code.shopify_api_create_discount_code
      if shopify_discount_code.present?
        @discount_code.shopify_discount_code_id = shopify_discount_code.id
        @discount_code.usage_count = shopify_discount_code.usage_count
        if @discount_code.save
          cc_money_payment.update_attributes(discount_code: @discount_code)
          flash[:notice] = "Discount Code created"
        else
          cc_money_payment.destroy
          flash[:notice] = "Discount Code not created properly!"
        end
      else
        cc_money_payment.destroy
        flash[:notice] = "Shopify API not working"
      end
    else
      flash[:notice] = "Payment not processed"
    end
    redirect_to discount_codes_path
  end

  private

    def webhook_params
      params.except(:controller, :action, :type)
    end

    def set_price_rule
      @price_rule = PriceRule.find_by_id(params[:price_rule_id])
    end

    def check_user_wallet
      current_user.update_wallet
      unless current_user.wallet >= @price_rule.cc
        flash[:alert] = "Not enough CC points"
        redirect_to :back
      end
    end
end
