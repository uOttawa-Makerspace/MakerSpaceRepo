# frozen_string_literal: true

# Sends the claim email of an unclaimed CC Money purchase again. Rows bought before the buyer's address was recorded
# have none, so the admin gives it and it is recorded; a recorded address cannot be replaced. Each resend revokes the
# links sent before. The mail is the one the shop order sends.
class Admin::CcMoneyClaimEmailsController < AdminAreaController
  def create
    cc_money = CcMoney.find(params[:cc_money_id])
    email = params[:email].to_s.strip

    if !cc_money.claimable?
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.already_linked")
    elsif email !~ URI::MailTo::EMAIL_REGEXP
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.email_invalid")
    elsif !cc_money.addressed_to?(email)
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.email_mismatch")
    else
      resend(cc_money, email)
    end
    redirect_to admin_cc_moneys_path
  end

  private

  # The new token replaces every link sent before; a row claimed in the meantime sends nothing.
  def resend(cc_money, email)
    token = cc_money.reissue_claim_token!(email)
    if token.nil?
      flash[:alert] = I18n.t("errors.admin.cc_money_claim_email.already_linked")
    else
      send_claim_mail(cc_money, email, token)
    end
  end

  def send_claim_mail(cc_money, email, token)
    MsrMailer.send_cc_money_email(email, cc_money.cc, token).deliver_later
    Rails.logger.info("CC claim email for cc_money #{cc_money.id} resent to #{email} by user #{current_user.id} at #{Time.current.iso8601}")
    flash[:notice] = "Claim email for #{cc_money.cc} CC sent to #{email} at #{I18n.l(Time.current, format: :short)}."
  end
end
