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
      "<span style='color: green'>Beg</span>"
    elsif lm.where(level: "Intermediate").present?
      "<span style='color: #969600'>Int</span>"
    elsif lm.where(level: "Advanced").present?
      "<span style='color: red'>Adv</span>"
    else
      "<span style='color: blue'>Master</span>"
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
    when "Beginner"
      "text-success"
    when "Intermediate"
      "text-warning"
    when "Advanced"
      "text-danger"
    end
  end

  def levels_ordered(training)
    result = training.learning_modules.pluck(:level).uniq.sort
    result.include?("Advanced") ? result = result.rotate(1) : result
    result
  end
end
