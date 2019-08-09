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
end
