namespace :users_without_tac do

  desc "get an array of usernames and emails of users
        that didn't sign the terms and conditions."
  task get_users: :environment do
    @users = User.unsigned_tac_users
    $emails = []
    @users.each do |user|
      #puts user['username'] + ", " + user['email']
      $emails << user['email']
    end
  end

end
