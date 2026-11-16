class ChatMessage < ApplicationRecord
  include DisplayUser

  belongs_to :job_order
  belongs_to :sender, class_name: 'User'
  # display_sender shows who wrote a message even when the account was deleted; notifications keep using +sender+.
  display_user_for :sender

  validates :message, presence: true
  validates :sender_id, presence: true

  scope :unread, ->(current_user) { 
    where.not(sender: current_user)
         .where(is_read: false)
  }

  # A message from the order's owner newer than every message from anyone else on the order.
  UNANSWERED_SQL = <<~SQL.squish
    chat_messages.sender_id = job_orders.user_id AND chat_messages.created_at > COALESCE((
      SELECT MAX(answers.created_at) FROM chat_messages answers
      WHERE answers.job_order_id = chat_messages.job_order_id AND answers.sender_id IS DISTINCT FROM job_orders.user_id
    ), '-infinity')
  SQL

  # How many messages of each order +reader+ has not read and did not send, keyed by order id; an order with none
  # is absent. One query however many orders.
  def self.unread_counts(job_orders, reader)
    where(job_order_id: job_orders.map(&:id)).unread(reader).group(:job_order_id).count
  end

  # How many of each order's newest messages its owner wrote in a row (not yet answered), keyed by
  # order id; an order with none is absent. One query however many orders.
  def self.unread_by_admin_counts(job_orders)
    joins(:job_order).where(job_order_id: job_orders.map(&:id)).where(UNANSWERED_SQL).group(:job_order_id).count
  end

  def timestamp
    if created_at.today?
      I18n.l(created_at, format: :time_only)
    else
      I18n.l(created_at, format: :short)
    end
  end

  # Emails everyone who should hear about this message, one email each: the order's owner, its assigned staff,
  # everyone who has posted in the chat and can still open the order, and the extra recipients in Setting.chat_extra_recipients; never the
  # author, never twice. Called by whoever posts the message, after it is saved. Nothing goes out for a draft
  # order, or when the author already posted in this chat within the last hour.
  def notify_participants
    return if recent_message_by_sender? || job_order.latest_status&.job_status == JobStatus.draft

    notification_emails.each { |email| ChatMessageMailer.new_message(self, email).deliver_later }
  end

  private

  def notification_emails
    posters = job_order.chat_messages.includes(:sender).map(&:sender)
    participants = [job_order.user, job_order.assigned_staff, *posters].select { |user| job_order.accessible_by?(user) }
    emails = participants.map(&:email) + extra_recipient_emails
    emails.uniq(&:downcase).reject { |email| email.casecmp?(sender.email) }
  end

  # Setting.chat_extra_recipients holds user ids and plain addresses.
  def extra_recipient_emails
    ids, addresses = Setting.chat_extra_recipients.partition { |entry| entry.match?(/\A\d+\z/) }
    User.where(id: ids).pluck(:email) + addresses
  end

  def recent_message_by_sender?
    ChatMessage.where(job_order_id: job_order_id, sender_id: sender_id)
              .where('created_at >= ?', 1.hour.ago)
              .where.not(id: id)
              .exists?
  end
end
