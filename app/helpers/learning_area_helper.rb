module LearningAreaHelper
  def get_lower_level_lm(training_id)
    lm =
      LearningModule
        .where.not(
          id:
            current_user.learning_module_tracks.completed.pluck(
              :learning_module_id
            )
        )
        .where(training_id: training_id)
    if lm.where(level: "Beginner").present?
      "<span style='color: green'>#{t('learning_module_track.level_short.beginner')}</span>"
    elsif lm.where(level: "Intermediate").present?
      "<span style='color: #969600'>#{t('learning_module_track.level_short.intermediate')}</span>"
    elsif lm.where(level: "Advanced").present?
      "<span style='color: red'>#{t('learning_module_track.level_short.advanced')}</span>"
    else
      "<span style='color: blue'>#{t('learning_module_track.level_short.master')}</span>"
    end
  end

  def get_next_lm(training_id)
    completed_ids = current_user.learning_module_tracks
                      .completed
                      .pluck(:learning_module_id)

    LearningModule
      .where(training_id: training_id)
      .where.not(id: completed_ids)
      .order(:order)
  end

  def return_text_color(level)
    case level
    when 'general'
      'text-body'
    when 'beginner'
      'text-success'
    when 'intermediate'
      'text-warning'
    when 'advanced'
      'text-danger'
    end
  end

  # How many of the modules the signed-in user completed, optionally only those of one level.
  def completed_modules_count(learning_modules, level = nil)
    learning_modules.count { |m| @completed_module_ids.include?(m.id) && (level.nil? || m.level == level) }
  end

  # The shortcut route's path in front of the shortcut itself, shown before the form's shortcut field.
  def learning_area_shortcut_prefix
    shortcut_learning_area_path('shortcut').delete_suffix('shortcut')
  end

  def levels_ordered(learning_modules)
    order = LearningModule.levels.keys
    learning_modules.map(&:level).uniq.sort_by { |level| order.index(level) }
  end
end
