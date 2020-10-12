# frozen_string_literal: true

module ProficientProjectsHelper
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

  def return_border_color(level)
    case level
    when 'Beginner'
      'w3-border-light-green'
    when 'Intermediate'
      'w3-border-yellow'
    when 'Advanced'
      'w3-border-red'
    end
  end

  def training_status(training_id)
    pp_missing = ProficientProject.where.not(id: current_user.order_items.awarded.pluck(:proficient_project_id)).where(training_id: training_id)
    levels_missing = pp_missing.pluck(:level)
    if levels_missing.include?("Beginner")
      "<span style='color: green'>Beg</span>"
    elsif levels_missing.include?("Intermediate")
      "<span style='color: #969600'>Int</span>"
    elsif levels_missing.include?("Advanced")
      "<span style='color: red'>Adv</span>"
    else
      "<span style='color: blue'>Master</span>"
    end
  end
end
