class ChatMessageMailer < ApplicationMailer
  # One message to one address: a notification never shows the other recipients' addresses.
  def new_message(chat_message, recipient_email)
    @chat_message = chat_message
    @job_order = chat_message.job_order
    @sender = chat_message.display_sender
    @sender_name = { fr: sender_name(:fr), en: sender_name(:en) }

    subject = "MakerRepo - Nouveau message // New message"
    
    mail(to: recipient_email, subject: subject)
  end

  private

  # A deleted account's name is not given to the recipient.
  def sender_name(locale)
    @sender.deleted? ? I18n.t('users.deleted_user', locale: locale) : @sender.name
  end
end