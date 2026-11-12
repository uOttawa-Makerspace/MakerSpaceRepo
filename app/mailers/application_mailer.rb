# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include ActionView::Helpers::SanitizeHelper 
  
  default from: "MakerRepo <ceedinfo@makerepo.com>"
  layout "mailer"

  self.delivery_job = ApplicationMailDeliveryJob

  # Every mail is rendered in the language its recipient saved on their account, whether it is delivered at once or
  # by a job. A recipient without an account, or with no saved choice, gets the site's default language.
  def mail(headers = {}, &)
    I18n.with_locale(recipient_locale(headers[:to])) { super }
  end

  private

  def recipient_locale(to)
    address = Array(to).one? ? Array(to).first.to_s : nil
    saved = User.where("lower(email) = ?", address.strip.downcase).pick(:locale) if address
    saved.presence || I18n.default_locale
  end
end
