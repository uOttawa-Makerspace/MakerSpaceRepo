class ChatMessageMailer < ApplicationMailer
  # One message to one address: a notification never shows the other recipients' addresses.
  def new_message(chat_message, recipient_email)
    @chat_message = chat_message
    @job_order = chat_message.job_order
    @sender = chat_message.sender

    subject = "MakerRepo - Nouveau message // New message"
    
    mail(to: recipient_email, subject: subject, respond_to: @sender.email)
  end
end