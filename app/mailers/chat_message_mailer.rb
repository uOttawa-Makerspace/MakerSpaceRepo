class ChatMessageMailer < ApplicationMailer
  def new_message(chat_message, recipients)
    @chat_message = chat_message
    @recipients = Array(recipients)
    @job_order = chat_message.job_order
    @sender = chat_message.sender

    subject = "MakerRepo - Nouveau message // New message"
    
    mail(to: @recipients.map(&:email), subject: subject)
  end
end