# frozen_string_literal: true

namespace :move_volunteer_to_volunteer_program do
  desc "Move volunteer to volunteer program"
  task move: :environment do
    @users = User.where(role: "volunteer")
    @users.each do |user|
      Program.join(user, Program::VOLUNTEER)
      user.update(role: "regular_user")
    end
  end
end
