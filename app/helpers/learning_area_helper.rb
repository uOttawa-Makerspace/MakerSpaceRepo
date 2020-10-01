module LearningAreaHelper
  def valid_url?(url)
    clean_url = strip_tags(url)
    url_regexp = /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$/ix
    clean_url =~ url_regexp and clean_url.include?("wiki.makerepo.com") ? true : false
  end

  def get_lower_level(training_id)
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
    lm = LearningModule.where.not(id: current_user.learning_module_tracks.completed.pluck(:learning_module_id)).where(training_id: training_id)
    if lm.where(level: "Beginner").present?
      lm.where(level: "Beginner")
    elsif lm.where(level: "Intermediate").present?
      lm.where(level: "Intermediate")
    elsif lm.where(level: "Advanced").present?
      lm.where(level: "Advanced")
    else
      []
    end
  end
end


