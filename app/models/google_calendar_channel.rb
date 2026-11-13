class GoogleCalendarChannel < ApplicationRecord
  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expiring_soon, -> { where("expires_at < ?", 2.days.from_now) }

  validates :channel_id, presence: true, uniqueness: true
  validates :resource_id, presence: true
  validates :expires_at, presence: true

  def self.current
    active.order(expires_at: :desc).first
  end

  # Google echoes the token given at registration in X-Goog-Channel-Token on every push. It is derived from the
  # channel id with the app's secret key, so each channel has its own and nothing needs storing.
  def self.token_for(channel_id)
    key = Rails.application.key_generator.generate_key("google calendar channel token")
    OpenSSL::HMAC.hexdigest("SHA256", key, channel_id.to_s)
  end

  # A push is accepted for a live channel whose resource id matches and whose token is the one issued for it.
  def self.valid_channel?(channel_id, resource_id, token)
    return false if channel_id.blank? || resource_id.blank? || token.blank?

    channel = active.find_by(channel_id: channel_id, resource_id: resource_id)
    channel.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, token_for(channel.channel_id))
  end
end