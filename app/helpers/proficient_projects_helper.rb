# frozen_string_literal: true

module ProficientProjectsHelper
  TRAINING_LEVEL_NAMES = User::TRAINING_LEVELS

  # FIXME we removed w3 lib, get rid of this
  def return_hover_and_text_colors(level)
    case level
    when 'Beginner'
      'w3-hover-border-light-green w3-hover-text-light-green'
    when 'Intermediate'
      'w3-hover-border-yellow w3-hover-text-yellow'
    when 'Advanced'
      'w3-hover-border-red w3-hover-text-red'
    end
  end

  # The user's standing in a training as a badge: the highest certified level, Newbie once they
  # have started it, else Not Started. Reads the user's progress, loaded once for all trainings.
  def training_status(training_id, user)
    standing = user.training_standing(training_id)
    return certification_status(standing) if TRAINING_LEVEL_NAMES.include?(standing)
    return content_tag(:span, '🐥 Newbie', class: 'text-body text-nowrap') if standing

    content_tag(:span, '🐣 Not Started', class: 'text-body-secondary text-nowrap')
  end
end
