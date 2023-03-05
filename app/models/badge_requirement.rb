# frozen_string_literal: true

class BadgeRequirement < ApplicationRecord
  belongs_to :proficient_project, optional: true
  belongs_to :badge_template, optional: true
end
