# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include ActionView::Helpers::SanitizeHelper 
  
  default from: "MakerRepo <ceedinfo@makerepo.com>"
  layout "mailer"

  self.delivery_job = ApplicationMailDeliveryJob

  # The shared team and role mailboxes. Several people read them, so a mail to one is in the site's default language
  # even when an account uses that address.
  TEAM_ADDRESSES = %w[makerspace@uottawa.ca mtc@uottawa.ca makerlab@uottawa.ca ceed@uottawa.ca
                      uottawa.makerepo@gmail.com volunteer@makerepo.com].freeze

  # Every mail to one member is rendered in the language they saved on their account, whether it is delivered at
  # once or by a job. A recipient without an account, or with no saved choice, a mail to several addresses, and a
  # mail to a team mailbox (TEAM_ADDRESSES or the maintenance address in Setting) get the site's default language.
  # A mail about an account sent to another address of its owner (the old or the new address of an email change)
  # passes locale: with the owner's saved language, since no account has that address yet or any more.
  # Subjects must be built inside mail() or with an explicit locale:, or they use the caller's language.
  def mail(headers = {}, &)
    I18n.with_locale(headers[:locale].presence || recipient_locale(headers[:to])) { super(headers.except(:locale), &) }
  end

  private

  # A subject built before mail() is called, in the recipient's saved language, from <mailer>.<action>.<key>.
  def subject_for(address, key = "subject", **values)
    I18n.t("#{mailer_name}.#{action_name}.#{key}", locale: recipient_locale(address), **values)
  end

  # A subject in French, then English ("<French> // <English>"), from <mailer>.<action>.<key>.
  def bilingual_subject(key, **values)
    %i[fr en].map { |locale| I18n.t("#{mailer_name}.#{action_name}.#{key}", locale:, **values) }.join(" // ")
  end

  def recipient_locale(to)
    address = member_address(to)
    saved = User.find_by(email: address)&.locale if address
    saved.presence || I18n.default_locale
  end

  # The address a mail is sent to when that is one member's, nil for several addresses or a team mailbox.
  def member_address(to)
    addresses = Array(to)
    address = addresses.first.to_s.strip if addresses.one?
    address unless address.nil? || team_address?(address)
  end

  def team_address?(address)
    TEAM_ADDRESSES.include?(address.downcase) || address.casecmp?(Setting.maintenance_email.to_s)
  end
end
