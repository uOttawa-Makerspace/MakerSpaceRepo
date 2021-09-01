# frozen_string_literal: true

namespace :send_update_profile do
  desc 'sends emails to update profile'
  task send_emails: :environment do
    max_bcc_at_once = 499
    emails = User.active.pluck(:email).in_groups_of(max_bcc_at_once, false)
    emails.each_with_index do |email_list, i|
      puts "Sending email ##{i}"
      MsrMailer.send_profile_update(email_list).deliver
    end
  end
end

