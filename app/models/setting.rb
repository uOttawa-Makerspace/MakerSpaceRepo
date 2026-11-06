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

  # Moves +key+ from +from+ to +to+ only if it still holds +from+ (nil meaning no row or an empty value). True for
  # the one caller that made the move. The conditional update takes the row lock, so concurrent callers cannot
  # both succeed.
  def self.swap(key, from, to)
    insert({ key: key }, unique_by: :key)
    where(key: key).where("value IS NOT DISTINCT FROM ?", from).update_all(value: to, updated_at: Time.current).positive?
  end
end
