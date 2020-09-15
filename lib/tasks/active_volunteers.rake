# frozen_string_literal: true

namespace :active_volunteers do
  desc 'Check if volunteers are active or not'
  task check_volunteers_status: :environment do
    User.joins(:programs).where(role: 'volunteer', programs: {program_type: 'Volunteer Program'}).find_each do |user|
      program = user.programs.find_by_program_type("Volunteer Program")
      if (user.last_seen_at.nil? || user.last_seen_at < 2.months.ago) && program.active == true
        program.update(active: false)
      elsif !user.last_seen_at.nil? && user.last_seen_at > 2.months.ago && program.active == false
        program.update(active: true)
      end
    end
  end

  desc 'Check if volunteers had at least one task completed'
  task check_volunteers_tasks_performance: :environment do
    User.joins(:programs).where(role: 'volunteer', programs: {program_type: 'Volunteer Program'}).find_each do |user|
      status = []
      program = user.programs.find_by_program_type("Volunteer Program")
      user.volunteer_task_joins.each do |vtj|
        status << vtj.volunteer_task.status
      end

      if status.include?('completed')
        program.update(active: true) if program.active != true
      else
        program.update(active: false) if program.active != false
      end
    end
  end
end
