# frozen_string_literal: true

namespace :users_without_waiver do
  desc 'sends emails to a list of emails'
  task send_emails: :environment do
    emails = []
    @users = User.no_waiver_users
    @users.each do |user|
      emails << user['email']
    end
    emails.each do |email|
      puts email
      MsrMailer.waiver_reminder_email(email).deliver
    end
  end
end
