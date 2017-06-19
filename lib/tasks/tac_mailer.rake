namespace :tac_mailer do

  desc "sends emails to a list of emails"
  task send_emails: :environment do
    emails = ['karimchukfeh@gmail.com', 'kchuk030@uottawa.ca']
    emails.each do |email|
      TacMailer.send_reminder_email(email).deliver
    end
  end

end
