class DiscountCodesController < DevelopmentProgramsController

  def index
    @discount_codes = current_user.discount_codes.order(:created_at => :desc)
  end

  def new
    @price_rules = PriceRule.all
  end

  def create
    price_rule = PriceRule.find_by_id(params[:price_rule_id])
    @discount_code = current_user.discount_codes.new
    @discount_code.code = DiscountCode.generate_code
    @discount_code.price_rule = price_rule
    shopify_discount_code = @discount_code.shopify_api_create_discount_code
    byebug
    if shopify_discount_code.present?
      @discount_code.shopify_discount_code_id = shopify_discount_code.id
      @discount_code.usage_count = shopify_discount_code.usage_count
      if @discount_code.save
        flash[:notice] = "Discount Code created"
      else
        flash[:notice] = "Discount Code not saved!"
      end
    else
      flash[:notice] = "Shopify API not working"
    end
    redirect_to :back
  end
end
