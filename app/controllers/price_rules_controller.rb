class PriceRulesController < DevelopmentProgramsController
  before_action :set_price_rule, only: [:show, :edit, :update, :destroy]

  # GET /price_rules
  # GET /price_rules.json
  def index
    @price_rules = PriceRule.all
  end

  # GET /price_rules/1
  # GET /price_rules/1.json
  def show
  end

  # GET /price_rules/new
  def new
    @price_rule = PriceRule.new
  end

  # GET /price_rules/1/edit
  def edit
  end

  # POST /price_rules
  # POST /price_rules.json
  def create
    @price_rule = PriceRule.new(price_rule_params)

    respond_to do |format|
      if @price_rule.save
        format.html { redirect_to @price_rule, notice: 'Price rule was successfully created.' }
        format.json { render :show, status: :created, location: @price_rule }
      else
        format.html { render :new }
        format.json { render json: @price_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /price_rules/1
  # PATCH/PUT /price_rules/1.json
  def update
    respond_to do |format|
      if @price_rule.update(price_rule_params)
        format.html { redirect_to @price_rule, notice: 'Price rule was successfully updated.' }
        format.json { render :show, status: :ok, location: @price_rule }
      else
        format.html { render :edit }
        format.json { render json: @price_rule.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /price_rules/1
  # DELETE /price_rules/1.json
  def destroy
    @price_rule.destroy
    respond_to do |format|
      format.html { redirect_to price_rules_url, notice: 'Price rule was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_price_rule
      @price_rule = PriceRule.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def price_rule_params
      params.require(:price_rule).permit(:title, :value, :cc)
    end
end
