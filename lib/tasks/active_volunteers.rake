# frozen_string_literal: true

namespace :active_volunteers do
  desc "Check if volunteers are active or not"
  task check_volunteers_status: :environment do
    Program.refresh_volunteer_activity!
  end

  desc "Check if volunteers had at least one task completed"
  task check_volunteers_tasks_performance: :environment do
    User.volunteers.find_each do |user|
      status = []
      program = user.programs.find_by_program_type("Volunteer Program")
      user.volunteer_task_joins.each do |vtj|
        status << vtj.volunteer_task.status
      end

      if status.include?("completed")
        program.update(active: true) if program.active != true
      else
        program.update(active: false) if program.active != false
      end
    end
  end
end
