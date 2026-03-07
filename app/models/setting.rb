class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.update(value: value)
    setting
  end

  def self.maintenance_email
    get("maintenance_notification_email")
  end

  def self.maintenance_email=(email)
    set("maintenance_notification_email", email)
  end
end