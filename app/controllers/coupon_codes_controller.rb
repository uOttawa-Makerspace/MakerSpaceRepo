class CouponCodesController < DevelopmentProgramsController
  before_action :admin_only

  def index
    @coupon_codes = CouponCode.unclaimed
    @user_codes = CouponCode.claimed
    @coupon_code = CouponCode.new
  end

  def create
    @coupon_code = CouponCode.new(coupon_code_params)
    if @coupon_code.save
      redirect_to coupon_codes_path,
                  notice: "Coupon code was successfully created."
    else
      render :index
    end
  end

  def edit
    @coupon_code = CouponCode.find(params[:id])
    if @coupon_code.update(coupon_code_params)
      redirect_to coupon_codes_path,
                  notice: "Coupon code was successfully updated."
    else
      render :edit
    end
  end

  def destroy
    @coupon_code = CouponCode.find(params[:id])
    @coupon_code.destroy
    redirect_to coupon_codes_path,
                notice: "Coupon code was successfully deleted."
  end

  def admin_only
    unless current_user.admin?
      redirect_to root_path, alert: "Admin access only."
    end
  end

  def coupon_code_params
    params.require(:coupon_code).permit(:code, :cc_cost, :dollar_cost)
  end
end
