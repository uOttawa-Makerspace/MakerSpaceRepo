namespace :users_without_waiver do

  desc "get an array of usernames and emails of users
        that didn't sign agree to the waiver."
  task get_users: :environment do
    @users = User.no_waiver_users
    @users.each do |user|
      puts user['email']
    end
  end

end
