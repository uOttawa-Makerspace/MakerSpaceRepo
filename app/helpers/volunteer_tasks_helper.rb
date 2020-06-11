# frozen_string_literal: true

module VolunteerTasksHelper
  def user_trainings
    user_trainings = Set.new
    current_user.certifications.find_each do |cert|
      user_trainings << cert.training_session.training_id
    end
    user_trainings
  end

  def volunteer_task_trainings
    volunteer_task_trainings = Set.new
    @volunteer_task.require_trainings.find_each do |rt|
      volunteer_task_trainings << rt.training_id
    end
    volunteer_task_trainings
  end
end
