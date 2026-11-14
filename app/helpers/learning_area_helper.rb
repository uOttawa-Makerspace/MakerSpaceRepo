module LearningAreaHelper
  # The text colour class of each level in the skills overview, lowest level first. Each one reads well on the light
  # and the dark theme.
  LOWEST_OPEN_LEVEL_CLASSES = {
    "beginner" => "text-success", "intermediate" => "text-warning-emphasis", "advanced" => "text-danger"
  }.freeze

  # The lowest level of the training at which the signed-in user still has a module to do ("Master" once none is left).
  # Reads the training's loaded learning_modules.
  def get_lower_level_lm(training)
    open_levels = get_next_lm(training).map(&:level)
    level = LOWEST_OPEN_LEVEL_CLASSES.keys.find { |key| open_levels.include?(key) }
    tag.span(t("learning_module_track.level_short.#{level || 'master'}"),
             class: LOWEST_OPEN_LEVEL_CLASSES.fetch(level, "text-info-emphasis"))
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
