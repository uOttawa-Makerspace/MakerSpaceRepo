module LearningModuleTrackHelper
  def return_button_class(status)
    case status
    when 'Not Started' then "btn-dark"
    when 'In progress' then "btn-warning"
    when 'Completed' then "btn-success"
    end
  end
end
