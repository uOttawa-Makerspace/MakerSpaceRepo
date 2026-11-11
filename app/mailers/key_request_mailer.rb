# frozen_string_literal: true

class KeyRequestMailer < ApplicationMailer
  # Tells the requester that an admin denied their key request, with the reason when one was
  # given. The reason is passed in, so the mail says what the admin wrote even if the request is
  # resubmitted before the mail is delivered. French first, then English, like the other mails sent to users. Nothing is sent when the
  # account was deleted or has no email.
  def send_key_request_denied(key_request_id, reason = nil)
    @key_request = KeyRequest.find(key_request_id)
    @reason = reason.presence
    @user = @key_request.user
    return if @user.nil? || @user.deleted? || @user.email.blank?

    @subject = "MakerRepo - #{I18n.t("key_request_mailer.denied.subject", locale: :fr)} // #{I18n.t("key_request_mailer.denied.subject", locale: :en)}"
    mail(to: @user.email, subject: @subject)
  end
end
