# frozen_string_literal: true

class JobAlertMailer < ApplicationMailer
  # items: JobAlert::Item list. Job arguments are never part of the mail.
  def alert(items, recipient_email)
    @items = items
    mail(to: recipient_email, subject: "MakerRepo | #{items.size} background job #{'problem'.pluralize(items.size)}")
  end
end
