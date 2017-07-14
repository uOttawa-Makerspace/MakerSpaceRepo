namespace :user_tac_status do

  desc "get an array of usernames and emails of users
        that didn't sign the terms and conditions."
  task check_status: :environment do
    @users = User.unsigned_users
    @users.each do |user|
      puts user['username'] + ", " + user['email']
    end
  end

end
