class CcMoneysController < ApplicationController
  before_action :signed_in, only: :redeem
  before_action :set_verifier, only: %i[link_cc_to_user redeem]

  def index
  end

  def link_cc_to_user
    @cc_token = params[:token]
    if @verifier.valid_message?(@cc_token)
      cc_id = @verifier.verify(@cc_token)
      @cc_money = CcMoney.find_by_id(cc_id)
      redirect_to cc_moneys_path, alert: "The CC Money has already been added to an account" if @cc_money.linked?
    else
      flash[:alert] = "Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com"
      redirect_to cc_moneys_path
    end
  end

  def redeem
    cc_token = params[:token]
    cc_id = @verifier.verify(cc_token)
    user = User.find_by(user_params)
    cc_money = CcMoney.find_by_id(cc_id)
    if !cc_money.linked? && user.present?
      cc_money.update(user: user, linked: true)
      flash[:notice] = "The CC Money has been added to #{user.name}"
    else
      flash[:alert] = "The CC Money has already been added to an account"
    end
    redirect_to cc_moneys_path
  end

  # def redeem
  #   cc_id = Rails.application.message_verifier(:cc).verify(params[:id])
  #   if CcMoney.find(cc_id).linked? == false
  #     CcMoney.find(cc_id).update(user_id: @user.id, linked: true)
  #     flash[:notice] = "The CC Money has been added to your wallet !"
  #     redirect_to cc_moneys_path
  #   else
  #     flash[:alert] = "The CC Money has already been added to an account"
  #     redirect_to cc_moneys_path
  #   end
  # end

  private

    def set_verifier
      @verifier = Rails.application.message_verifier(:cc)
    end

    def user_params
      params.require(:user).permit(:email)
    end
end
