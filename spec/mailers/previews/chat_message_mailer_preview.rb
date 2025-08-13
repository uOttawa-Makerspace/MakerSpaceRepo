# Preview all emails at http://localhost:3000/rails/mailers/chat_message_mailer_mailer
class ChatMessageMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/chat_message_mailer_mailer/new_message
  def new_message
    ChatMessageMailer.new_message(ChatMessage.first, User.where(id: [13_252, 1607]))
  end

end
