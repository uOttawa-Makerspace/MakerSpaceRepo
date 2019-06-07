namespace :active_volunteers do

  desc "Check if volunteers are active or not"
  task check_volunteers_status: :environment do
    User.where(role: "Volunteer").find_each do |user|


    end
  end
end
