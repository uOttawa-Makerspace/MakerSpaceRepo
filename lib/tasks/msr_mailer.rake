namespace :msr_mailer do
  desc "sends emails to a list of emails"
  task send_emails: :environment do
    emails = ['abc@abc.com', 'xyz@xyz.ca']
    emails.each do |email|
      MsrMailer.tac_reminder_email(email).deliver_now
    end
  end
end
