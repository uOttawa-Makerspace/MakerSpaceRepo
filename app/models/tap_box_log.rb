class TapBoxLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  CARD_TAP         = "card_tap"
  SIGN_IN          = "sign_in"
  SIGN_OUT         = "sign_out"
  ERROR            = "error"
  WARNING          = "warning"
  INFO             = "info"
  MEMBERSHIP_CHECK = "membership_check"

  EVENT_TYPES = [CARD_TAP, SIGN_IN, SIGN_OUT, ERROR, WARNING, INFO, MEMBERSHIP_CHECK].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :message, presence: true

  scope :recent, -> { order(created_at: :desc).limit(500) }

  after_create_commit :broadcast_log

  def self.log!(event_type:, message:, card_number: nil, user: nil, space: nil, mac_address: nil, details: nil)
    create!(
      event_type: event_type,
      message: message,
      card_number: card_number,
      user: user,
      space: space,
      mac_address: mac_address,
      details: details
    )
  rescue => e
    Rails.logger.error("[TapBoxLog] Failed to write log: #{e.message}")
  end

  # Clean up logs older than 30 days
  def self.purge_old!(days: 30)
    where("created_at < ?", days.days.ago).delete_all
  end

  def as_broadcast
    {
      id: id,
      event_type: event_type,
      card_number: card_number,
      user_name: user&.name,
      user_id: user_id,
      space_name: space&.name,
      space_id: space_id,
      mac_address: mac_address,
      message: message,
      details: details,
      created_at: created_at.strftime("%Y-%m-%d %H:%M:%S.%L")
    }
  end

  private

  def broadcast_log
    TapBoxConsoleChannel.broadcast_log(self)
  end
end