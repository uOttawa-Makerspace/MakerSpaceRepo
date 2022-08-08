# frozen_string_literal: true

namespace :update_profile do
  desc "sends emails to update profile"
  task :send_emails, [:removed_emails] => [:environment] do |t, args|
    # HOW TO USE THE RAKE TASK
    # rake "update_profile:send_emails", if you want to remove particular emails
    # (In case of error while sending them for example), you can do rake "update_profile:send_emails[a@a.ca b@b.ca]"
    # DO NOT ADD commas or it will break the rake task

    emails_to_remove = args.removed_emails.split(" ")
    max_bcc_at_once = 498
    emails =
      (User.active.pluck(:email) - emails_to_remove).in_groups_of(
        max_bcc_at_once,
        false
      )
    emails.each_with_index do |email_list, i|
      puts "Sending email ##{i}"
      MsrMailer.send_profile_update(email_list).deliver_now
    end
  end
end
