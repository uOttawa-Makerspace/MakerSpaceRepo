class ChatMessage < ApplicationRecord
  belongs_to :job_order
  belongs_to :sender, class_name: 'User'

  validates :message, presence: true

  after_commit :schedule_notification_email, on: :create

  scope :unread, ->(current_user) { 
    where.not(sender: current_user)
         .where(is_read: false)
  }

  def self.count_unread_by_admin(job_order)
    where(job_order: job_order)
      # .where.not(sender_id: current_user.id)
      .order(created_at: :desc)
      .take_while { |msg| msg.sender_id == job_order.user_id }
      .count
  end

  def timestamp
    if created_at.today?
      I18n.l(created_at, format: :time_only)
    else
      I18n.l(created_at, format: :short)
    end
  end

  private

  def schedule_notification_email
    return if recent_message_by_sender? || job_order.job_order_statuses.last&.job_status != JobStatus::DRAFT

    ChatNotificationJob.set(wait: 1.hour).perform_later(id)
  end

  def recent_message_by_sender?
    ChatMessage.where(job_order_id: job_order_id, sender_id: sender_id)
              .where('created_at >= ?', 1.hour.ago)
              .where.not(id: id)
              .exists?
  end
end