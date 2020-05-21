class BadgeTemplate < ActiveRecord::Base
  def self.get_badge_name(badge_id)
    badge_template = self.find_by(badge_id: badge_id)
    badge_template.present? ? badge_template.badge_name : "Name not found"
  end
end
