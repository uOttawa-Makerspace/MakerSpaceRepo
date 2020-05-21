class Badge < ActiveRecord::Base
  belongs_to :user

  def self.get_badge_name(badge_id)
    if BadgeTemplate.where(badge_id: badge_id).first.present?
      return BadgeTemplate.where(badge_id: badge_id).first.badge_name
    else
      return "Name not found"
    end
  end
end
