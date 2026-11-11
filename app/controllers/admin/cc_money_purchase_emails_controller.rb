# frozen_string_literal: true

# Corrects the purchase email of an unclaimed CC Money row (a mistyped address at checkout) and mails the claim
# link to the corrected address. Links sent before stop working. The change is recorded with the admin who made it.
class Admin::CcMoneyPurchaseEmailsController < AdminAreaController
  def update
    cc_money = CcMoney.find(params[:cc_money_id])
    outcome = cc_money.correct_purchase_email(params[:email], by: current_user)
    if outcome == :corrected
      send_claim_mail(cc_money)
      flash[:notice] = corrected_notice(cc_money)
    else
      flash[:alert] = I18n.t("errors.admin.cc_money_purchase_email.#{outcome}")
    end
    redirect_to admin_cc_moneys_path
  end

  private

  # The generation was raised under the row lock, so this token replaces every link sent before.
  def send_claim_mail(cc_money)
    MsrMailer.send_cc_money_email(cc_money.purchaser_email, cc_money.cc, cc_money.claim_token).deliver_later
  end

  def corrected_notice(cc_money)
    I18n.t("admin.cc_money_purchase_email.corrected", cc: cc_money.cc, email: cc_money.purchaser_email)
  end
end
