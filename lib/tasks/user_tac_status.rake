namespace :user_tac_status do

  desc "get a json of usernames and emails of users
        that didn't sign the terms and conditions."
  task check_status: :environment do
    users_json = unsigned_users
    users_json.each do |user|
      puts user['username'] + ", " + user['email']
    end

  end


  private

  def unsigned_users
    users = User.where(terms_and_conditions: false).select(:username, :email).to_json
    return JSON.parse(users)
  end

end
