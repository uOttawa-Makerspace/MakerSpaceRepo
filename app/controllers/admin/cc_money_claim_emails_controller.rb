# frozen_string_literal: true

# Sends the claim email of an unclaimed CC Money purchase again. The row does not store the buyer's address,
# so the admin gives it. The mail and its token are the ones the shop order sends.
class Admin::CcMoneyClaimEmailsController < AdminAreaController
  def create
    cc_money = CcMoney.find(params[:cc_money_id])
    email = params[:email].to_s.strip

    if !cc_money.claimable?
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.already_linked")
    elsif email !~ URI::MailTo::EMAIL_REGEXP
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.email_invalid")
    else
      resend(cc_money, email)
    end
    redirect_to admin_cc_moneys_path
  end

  private

  def resend(cc_money, email)
    MsrMailer.send_cc_money_email(email, cc_money.cc, cc_money.claim_token).deliver_later
    Rails.logger.info("CC claim email for cc_money #{cc_money.id} resent to #{email} by user #{current_user.id} at #{Time.current.iso8601}")
    flash[:notice] = "Claim email for #{cc_money.cc} CC sent to #{email} at #{I18n.l(Time.current, format: :short)}."
  end
end
