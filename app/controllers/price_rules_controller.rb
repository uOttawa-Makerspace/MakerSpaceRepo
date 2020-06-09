class PriceRulesController < DevelopmentProgramsController
  before_action :admin_access
  before_action :set_price_rule, only: [:edit, :update, :destroy]
  before_action :check_discount_codes, only: [:edit, :update]

  def index
    @price_rules = PriceRule.all
  end

  def new
    @price_rule = PriceRule.new
  end

  def edit
  end

  def create
    @price_rule = PriceRule.new(price_rule_params)

    @price_rule.shopify_price_rule_id = PriceRule.create_price_rule(@price_rule.title, @price_rule.value)

    respond_to do |format|
      if @price_rule.save

        format.html { redirect_to price_rules_path, notice: 'Price rule was successfully created.' }
        format.json { render :index, status: :created, location: @price_rule }
      else
        format.html { render :new }
        format.json { render json: @price_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @price_rule.update(price_rule_params)

        PriceRule.update_price_rule(@price_rule.shopify_price_rule_id, @price_rule.title, @price_rule.value)

        format.html { redirect_to price_rules_url, notice: 'Price rule was successfully updated.' }
        format.json { render :index, status: :ok }
      else
        format.html { render :edit }
        format.json { render json: @price_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    PriceRule.delete_price_rule_from_shopify(@price_rule.shopify_price_rule_id)
    @price_rule.destroy
    respond_to do |format|
      format.html { redirect_to price_rules_url, notice: 'Price rule was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

    def admin_access
      unless current_user.admin?
        flash[:alert] = "Forbbiden Area"
        redirect_to root_path
      end
    end
    def set_price_rule
      @price_rule = PriceRule.find(params[:id])
    end

    def price_rule_params
      params.require(:price_rule).permit(:title, :value, :cc)
    end

    def check_discount_codes
      unless !@price_rule.has_discount_codes?
        flash[:alert] = "This price rule cannot be eddited/deleted because it has already discount codes"
        redirect_to price_rules_path
      end
    end
end
