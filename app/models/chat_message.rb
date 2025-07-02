class ChatMessage < ApplicationRecord
  belongs_to :job_order
  belongs_to :sender, class_name: 'User'

  validates :message, presence: true

  after_create :send_notification_email, if: :should_send_email?

  scope :unread, ->(current_user) { 
    where.not(sender: current_user)
         .where(is_read: false)
  }

  def timestamp
    if created_at.today?
      I18n.l(created_at, format: :time_only)
    else
      I18n.l(created_at, format: :short)
    end
  end

  private

  def should_send_email?
    # Check if this is the first message for the job order
    is_first_message = ChatMessage.where(job_order: job_order)
                                  .where.not(id: id)
                                  .empty?
    
    return false if is_first_message

    # Check if the most recent message from this sender was more than 45 minutes ago
    last_message = ChatMessage.where(sender: sender, job_order: job_order)
                              .where.not(id: id)
                              .order(created_at: :desc)
                              .first
                              
    last_message.nil? || last_message.created_at < 45.minutes.ago
  end

  def send_notification_email
    recipients = if job_order.user_id == sender_id
                  # Alex and Justine
                  User.where(id: [25, 1607]).to_a
                  # User.where(id: [13_252]).to_a
                else
                  [job_order.user]
                end

    ChatMessageMailer.new_message(self, recipients).deliver_later if recipients.any?
  end
end