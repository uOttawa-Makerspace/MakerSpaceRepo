class ChatNotificationJob < ApplicationJob
  self.queue_adapter = :solid_queue

  def perform(chat_message_id)
    chat = ChatMessage.find_by(id: chat_message_id)
    return if chat.nil? || chat.recent_message_by_sender? # Double check

    recipients = chat.job_order.chat_messages
                     .where.not(sender_id: chat.sender_id)
                     .select(:sender_id)
                     .distinct
                     .map(&:sender)
                     .uniq

    additional_recipients = User.where(id: [25, 1607])
    all_recipients = (recipients + additional_recipients).uniq - [chat.sender]

    ChatMessageMailer.new_message(chat, all_recipients).deliver_later if all_recipients.any?
  end
end
