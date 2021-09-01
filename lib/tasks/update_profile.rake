# frozen_string_literal: true

namespace :update_profile do
  desc 'sends emails to update profile'
  task send_emails: :environment do
    max_bcc_at_once = 98
    emails = User.active.pluck(:email).in_groups_of(max_bcc_at_once, false)
    emails.each_with_index do |email_list, i|
      puts "Sending email ##{i}"
      MsrMailer.send_profile_update(email_list).deliver_now
    end
  end
end

