module LearningAreaHelper
  def get_lower_level_lm(training_id)
    lm = LearningModule.where.not(id: current_user.learning_module_tracks.completed.pluck(:learning_module_id)).where(training_id: training_id)
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
    level = TrainingSession.where(training_id: training_id).pluck(:level)
    if level.include?("Advanced")
      "<span style='color: blue'>Master</span>"
    elsif level.include?("Intermediate")
      "<span style='color: red'>Adv</span>"
    elsif level.include?("Beginner")
      "<span style='color: #969600'>Int</span>"
    else
      "<span style='color: green'>Beg</span>"
    end
  end

  def return_text_color(level)
    case level
    when 'Beginner' then 'text-success'
    when 'Intermediate' then 'text-warning'
    when 'Advanced' then 'text-danger'
    end
  end

  def levels_ordered(training)
    result = training.learning_modules.pluck(:level).uniq.sort
    result.include?('Advanced') ? result = result.rotate(1) : result
    result
  end
end


