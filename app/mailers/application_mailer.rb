# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include ActionView::Helpers::SanitizeHelper 
  
  default from: "MakerRepo <ceedinfo@makerepo.com>"
  layout "mailer"

  self.delivery_job = ApplicationMailDeliveryJob

  # Every mail is rendered in the language its recipient saved on their account, whether it is delivered at once or
  # by a job. A recipient without an account, or with no saved choice, gets the site's default language.
  # A mail about an account sent to another address of its owner (the old or the new address of an email change)
  # passes locale: with the owner's saved language, since no account has that address yet or any more.
  # Subjects must be built inside mail() or with an explicit locale:, or they use the caller's language.
  def mail(headers = {}, &)
    I18n.with_locale(headers[:locale].presence || recipient_locale(headers[:to])) { super(headers.except(:locale), &) }
  end

  private

  def recipient_locale(to)
    address = Array(to).one? ? Array(to).first.to_s : nil
    saved = User.find_by(email: address.strip)&.locale if address
    saved.presence || I18n.default_locale
  end
end
