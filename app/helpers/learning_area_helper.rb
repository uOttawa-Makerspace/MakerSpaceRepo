module LearningAreaHelper
  # The colour of each level in the skills overview, lowest level first.
  LOWEST_OPEN_LEVEL_COLORS = { "beginner" => "green", "intermediate" => "#969600", "advanced" => "red" }.freeze

  # The lowest level of the training at which the signed-in user still has a module to do ("Master" once none is left).
  # Reads the training's loaded learning_modules.
  def get_lower_level_lm(training)
    open_levels = get_next_lm(training).map(&:level)
    level = LOWEST_OPEN_LEVEL_COLORS.keys.find { |key| open_levels.include?(key) }
    color = LOWEST_OPEN_LEVEL_COLORS.fetch(level, "blue")
    "<span style='color: #{color}'>#{t("learning_module_track.level_short.#{level || 'master'}")}</span>"
  end

  # The training's modules the signed-in user has not completed yet, in their set order.
  def get_next_lm(training)
    training.learning_modules_remaining(current_user)
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
