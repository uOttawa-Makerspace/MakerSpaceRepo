namespace :active_volunteers do

  desc "Check if volunteers are active or not"
  task check_volunteers_status: :environment do
    User.where(role: "volunteer").joins(:skill).find_each do |user|
      if (user.last_seen_at.nil? || user.last_seen_at < 2.month.ago) && user.skill.active == true
        skill = user.skill
        skill.update_attributes(active: false)
      elsif !user.last_seen_at.nil? && user.last_seen_at > 2.month.ago && user.skill.active == false
        skill = user.skill
        skill.update_attributes(active: true)
      end
    end
  end

  desc "Check if volunteers had at least one task completed"
  task check_volunteers_tasks_performance: :environment do
    User.where(role: "volunteer").joins(:skill).find_each do |user|
      status = []
      skill = user.skill
      user.volunteer_task_joins.each do |vtj|
        status << vtj.volunteer_task.status
      end

      if status.include?("completed")
        skill.update_attributes(active: true) if skill.active != true
      else
        skill.update_attributes(active: false) if skill.active != false
      end
    end
  end
end
