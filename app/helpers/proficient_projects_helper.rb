# frozen_string_literal: true

module ProficientProjectsHelper
  def return_hover_and_text_colors(proficient_project_level)
    case proficient_project_level
    when 'Beginner'
      'w3-hover-border-light-green w3-hover-text-light-green'
    when 'Intermediate'
      'w3-hover-border-yellow w3-hover-text-yellow'
    when 'Advanced'
      'w3-hover-border-red w3-hover-text-red'
    end
  end

  def return_border_color(proficient_project_level)
    case proficient_project_level
    when 'Beginner'
      'w3-border-light-green'
    when 'Intermediate'
      'w3-border-yellow'
    when 'Advanced'
      'w3-border-red'
    end
  end
end
