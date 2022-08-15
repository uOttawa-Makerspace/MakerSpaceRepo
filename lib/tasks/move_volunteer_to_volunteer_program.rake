# frozen_string_literal: true

namespace :move_volunteer_to_volunteer_program do
  desc "Move volunteer to volunteer program"
  task move: :environment do
    @users = User.where(role: "volunteer")
    @users.each do |user|
      if Program.create(
           user_id: user.id,
           program_type: Program::VOLUNTEER,
           active: true
         )
        user.update(role: "regular_user")
      end
    end
  end
end
