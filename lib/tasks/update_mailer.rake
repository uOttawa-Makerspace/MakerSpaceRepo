namespace :update_mailer do
  #not sure if this is correct
  desc "send update info email to old users"
  task :send_email => :environment do
    @old_users = User.unknown_identity
    @old_users.each do |user|
      UpdateMailer.update_identity(user).deliver
    end
  end
end
