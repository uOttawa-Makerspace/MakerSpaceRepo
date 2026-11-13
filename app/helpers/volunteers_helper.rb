# frozen_string_literal: true

module VolunteersHelper
  # A training level (stored in English, such as "Beginner") in the current language; an unknown level as stored.
  def training_level_name(level)
    t(level.to_s.downcase, scope: "volunteer_area.levels", default: level.to_s)
  end
end
