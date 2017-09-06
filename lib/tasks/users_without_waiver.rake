namespace :users_without_waiver do

  desc "get an array of usernames and emails of users
        that didn't sign agree to the waiver."
  task get_users: :environment do
    @emails = []
    @users = User.no_waiver_users
    @users.each do |user|
      @emails << user['email']
    end
  end

  desc "sends emails to a list of emails"
  task send_emails: :environment do
    @emails.each do |email|
      MsrMailer.waiver_reminder_email(email).deliver
    end
  end

end
