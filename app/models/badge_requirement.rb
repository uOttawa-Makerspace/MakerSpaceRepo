# frozen_string_literal: true

class BadgeRequirement < ApplicationRecord
  belongs_to :proficient_project
  belongs_to :badge_template
end
