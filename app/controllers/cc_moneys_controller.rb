class CcMoneysController < SessionsController
  before_action :with_development_header
  before_action :signed_in, only: %i[link_cc_to_user redeem]
  before_action :load_claim, only: %i[link_cc_to_user redeem]

  def index
    if signed_in?
      # A page view only reads: the balance is the ledger sum (uncached), no lock and no cache
      # write (the cached users.wallet is written only by spends and credits).
      @user_wallet = CcMoney.uncached { current_user.get_total_cc }
      @cc_activities = current_user.cc_moneys.order(created_at: :desc).limit(10)
    end
  end

  # Confirmation page for the purchaser; the claim is checked in load_claim.
  def link_cc_to_user; end

  # Credits the signed-in account only (load_claim has checked it is the purchaser's).
  def redeem
    link_to(@cc_money, current_user)
  end

  private

  def link_to(cc_money, user)
    case cc_money.link_to(user)
    when :linked
      flash[:notice] = "The CC Money has been added to #{user.name}"
      redirect_to cc_moneys_path
    when :already_linked then refuse_cc(:already_linked)
    when :superseded then refuse_cc(:token_invalid)
    else refuse_cc(:not_linked, cc_money)
    end
  end

  # Every refusal goes back to the CC money page with the message for its own cause.
  def refuse_cc(cause, record = nil)
    key = "errors.shop.cc_money.#{cause}"
    flash[:alert] = record ? validation_message(record, key) : I18n.t(key)
    redirect_to cc_moneys_path
  end

  # Finds the row the token names and refuses, with the message for its own cause, a token that is not
  # valid (garbage, expired, or replaced by a resend), a row that is gone or already claimed, and an
  # account other than the purchaser's. A redirect here stops the action.
  def load_claim
    @cc_token = params[:token]
    @cc_money = CcMoney.for_claim_token(@cc_token)
    return refuse_cc(:token_invalid) if @cc_money.nil?
    return refuse_cc(:already_linked) if @cc_money.linked?

    refuse_cc(:not_purchaser) unless @cc_money.claimable_by?(current_user)
  rescue ActiveRecord::RecordNotFound
    refuse_cc(:not_found)
  end
end
