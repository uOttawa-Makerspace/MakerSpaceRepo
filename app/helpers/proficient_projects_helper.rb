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
    level = Certification.joins(:user, :training_session).where(training_sessions: { training_id: training_id }, user: current_user ).pluck(:level)
    div = Proc.new{ |color, level| "<span class='float-right' style='color: #{color}'>#{level}</span>" }
    if level.include?("Advanced")
      div.call('red', '🦅 Advanced')
    elsif level.include?("Intermediate")
      div.call('#969600', '🦩 Intermediate')
    elsif level.include?("Beginner")
      div.call('green', '🦆 Beginner')
    else
      training = Training.find(training_id)
      learning_modules_completed = training.learning_modules.joins(:learning_module_tracks).where(learning_module_tracks: {user: current_user, status: 'Completed'}).present?
      proficient_projects_completed = training.proficient_projects.where(id: current_user.order_items.awarded.pluck(:proficient_project_id)).present?
      if learning_modules_completed || proficient_projects_completed
        div.call('black', '🐥 Newbie')
      else
        div.call('gray', '🐣 Not Started')
      end
    end
  end

  def return_levels(training_id, user_id)
    current_status = ProficientProject.training_status(training_id, user_id)
    case current_status
    when 'Beginner' then ['Beginner']
    when 'Intermediate' then ['Beginner', 'Intermediate']
    when 'Advanced' then ['Beginner', 'Intermediate', 'Advanced']
    end
  end
end
