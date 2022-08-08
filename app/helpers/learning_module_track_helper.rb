module LearningModuleTrackHelper
  def return_button_class(status)
    case status
    when "Not Started"
      "btn-dark"
    when "In progress"
      "btn-warning"
    when "Completed"
      "btn-success"
    end
  end
end
