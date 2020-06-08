class DiscountCodesController < DevelopmentProgramsController
  def create
    @discount_code = DiscountCode.new
    @discount_code.code = DiscountCode.generate_code
    @discount_code.price_rule_id = params[:price_rule_id]
    shopify_discount_code = @discount_code.shopify_api_create_discount_code
    if shopify_discount_code.present?
      @discount_code.shopify_discount_code_id = shopify_discount_code.id
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
