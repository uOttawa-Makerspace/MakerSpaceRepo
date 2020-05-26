class BadgeRequirement < ActiveRecord::Base
  belongs_to :proficient_project
  belongs_to :badge_template
end
