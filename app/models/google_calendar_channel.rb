class GoogleCalendarChannel < ApplicationRecord
  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expiring_soon, -> { where("expires_at < ?", 2.days.from_now) }

  validates :channel_id, presence: true, uniqueness: true
  validates :resource_id, presence: true
  validates :expires_at, presence: true

  def self.current
    active.order(expires_at: :desc).first
  end

  def self.valid_channel?(channel_id, resource_id)
    exists?(channel_id: channel_id, resource_id: resource_id)
  end
end