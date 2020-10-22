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
    if level.include?("Advanced")
      "<span style='color: red'>Advanced</span>"
    elsif level.include?("Intermediate")
      "<span style='color: #969600'>Intermediate</span>"

    elsif level.include?("Beginner")
      "<span style='color: green'>Beginner</span>"
    else
      training = Training.find(training_id)
      learning_modules_completed = training.learning_modules.joins(:learning_module_tracks).where(learning_module_tracks: {user: current_user, status: 'Completed'}).present?
      if learning_modules_completed
        "<span style='color: green'>Newbie</span>"
      else
        "<span style='color: gray'>Not Started</span>"
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
