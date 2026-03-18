# frozen_string_literal: true

module ProficientProjectsHelper
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

  def return_border_color(level)
    case level
    when 'Beginner'
      'border-success'
    when 'Intermediate'
      'w3-border-yellow'
    when 'Advanced'
      'w3-border-red'
    end
  end
  def training_status(training_id, user_id)
    user = User.find(user_id)
    level =
      Certification
        .joins(:user, :training_session)
        .where(training_sessions: { training_id: training_id }, user: user)
        .pluck(:level)

    return certification_status('Advanced') if level.include?('Advanced')
    if level.include?('Intermediate')
      return certification_status('Intermediate')
    end
    return certification_status('Beginner') if level.include?('Beginner')

    training = Training.find(training_id)

    started =
      training
        .learning_modules
        .joins(:learning_module_tracks)
        .where(learning_module_tracks: { user: user, status: 'Completed' })
        .exists? ||
        training
          .proficient_projects
          .where(id: user.order_items.awarded.pluck(:proficient_project_id))
          .exists?

    if started
      content_tag(:span, '🐥 Newbie', style: 'color: black; white-space: nowrap')
    else
      content_tag(
        :span,
        '🐣 Not Started',
        style: 'color: gray; white-space: nowrap'
      )
    end
  end

  def return_levels(training_id, user_id)
    current_status = ProficientProject.training_status(training_id, user_id)
    case current_status
    when 'Beginner'
      ['Beginner']
    when 'Intermediate'
      %w[Beginner Intermediate]
    when 'Advanced'
      %w[Beginner Intermediate Advanced]
    end
  end
end
