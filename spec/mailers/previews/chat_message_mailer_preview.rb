# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/chat_message_mailer
class ChatMessageMailerPreview < ActionMailer::Preview
  def new_message
    chat_message = ChatMessage.last || mock_chat_message
    recipients = if chat_message.persisted?
                   [chat_message.job_order.user]
                 else
                   [mock_recipient]
                 end

    ChatMessageMailer.new_message(chat_message, recipients)
  end

  private

  def mock_chat_message
    sender = User.new(
      id: 1,
      name: "John Doe",
      email: "john.doe@example.com"
    )

    job_order = JobOrder.new(id: 12345)

    ChatMessage.new(
      id: 1,
      message: "Bonjour! This is a sample message regarding your job order. Please review and let me know if you have any questions.",
      sender: sender,
      job_order: job_order
    )
  end

  def mock_recipient
    User.new(
      id: 2,
      name: "Jane Smith",
      email: "jane.smith@example.com"
    )
  end
end