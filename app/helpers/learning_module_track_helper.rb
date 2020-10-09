module LearningModuleTrackHelper
  def return_button_class(status)
    case status
    when 'Not Started' then "btn-outline-dark"
    when 'In progress' then "btn-outline-warning"
    when 'Completed' then "btn-outline-success"
    end
  end
end
