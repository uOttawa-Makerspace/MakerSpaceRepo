class CcMoneysController < ApplicationController
  before_action :signed_in, only: :redeem

  def index
  end

  def redeem
    cc_id = Rails.application.message_verifier(:cc).verify(params[:id])
    if CcMoney.find(cc_id).linked? == false
      CcMoney.find(cc_id).update(user_id: @user.id, linked: true)
      flash[:notice] = "The CC Money has been added to your wallet !"
      redirect_to cc_moneys_path
    else
      flash[:alert] = "The CC Money has already been added to an account"
      redirect_to cc_moneys_path
    end
  end
end
