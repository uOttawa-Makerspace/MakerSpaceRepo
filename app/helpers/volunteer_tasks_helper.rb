module VolunteerTasksHelper

  def return_active(active)
    case active
    when true
      "Yes"
    when false
      "No"
    end
  end

  def user_trainings
    user_trainings = Set.new
    current_user.training_sessions.find_each do |ts|
      user_trainings << ts.training_id
    end
    return user_trainings
  end

  def volunteer_task_trainings
    volunteer_task_trainings = Set.new
    @volunteer_task.require_trainings.find_each do |rt|
      volunteer_task_trainings << rt.training_id
    end
    return volunteer_task_trainings
  end
end
