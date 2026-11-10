class CcMoneysController < SessionsController
  before_action :with_development_header
  before_action :signed_in, only: %i[link_cc_to_user redeem]
  before_action :set_verifier, only: %i[link_cc_to_user redeem]

  def index
    if signed_in?
      # A page view only reads: the balance is the ledger sum (uncached), no lock and no cache
      # write (the cached users.wallet is written only by spends and credits).
      @user_wallet = CcMoney.uncached { current_user.get_total_cc }
      @cc_activities = current_user.cc_moneys.order(created_at: :desc).limit(10)
    end
  end

  def link_cc_to_user
    @cc_token = params[:token]
    return refuse_cc(:token_invalid) unless @verifier.valid_message?(@cc_token)

    @cc_money = CcMoney.find_by_id(@verifier.verify(@cc_token))
    return refuse_cc(:not_found) if @cc_money.nil?

    refuse_cc(:already_linked) if @cc_money.linked?
  end

  def redeem
    cc_id = @verifier.verified(params[:token])
    return refuse_cc(:token_invalid) if cc_id.nil?

    cc_money = CcMoney.find_by_id(cc_id)
    return refuse_cc(:not_found) if cc_money.nil?
    return refuse_cc(:already_linked) if cc_money.linked?

    user = User.find_by(email: user_params[:email])
    return refuse_cc(:user_not_found) if user.nil?

    link_to(cc_money, user)
  end

  private

  def link_to(cc_money, user)
    if cc_money.link_to(user)
      flash[:notice] = "The CC Money has been added to #{user.name}"
      redirect_to cc_moneys_path
    elsif cc_money.linked?
      refuse_cc(:already_linked)
    else
      refuse_cc(:not_linked, cc_money)
    end
  end

  # Every refusal goes back to the CC money page with the message for its own cause.
  def refuse_cc(cause, record = nil)
    key = "errors.shop.cc_money.#{cause}"
    flash[:alert] = record ? validation_message(record, key) : I18n.t(key)
    redirect_to cc_moneys_path
  end

  def set_verifier
    @verifier = Rails.application.message_verifier(:cc)
  end

  def user_params
    params.require(:user).permit(:email)
  end
end