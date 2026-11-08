# frozen_string_literal: true

namespace :update_profile do
  # Mails the profile update request once per calendar year, in BCC groups. A second run in the same year mails
  # nobody, an interrupted run continues after the last group claimed, and FORCE=1 mails everyone again.
  # Usage: rake "update_profile:send_emails" or, to leave out some addresses, rake "update_profile:send_emails[a@a.ca b@b.ca]"
  # (separate addresses with spaces, not commas).
  desc "sends emails to update profile"
  task :send_emails, [:removed_emails] => [:environment] do |_t, args|
    emails_to_remove = args.removed_emails.to_s.split
    max_bcc_at_once = 498
    run = BulkMailRun.new("update_profile", Time.zone.today.year, force: ENV["FORCE"] == "1")
    if run.done?
      puts "The profile update mail was already sent this year; run with FORCE=1 to send it again."
    else
      recipients = User.active.not_deactivated.where.not(email: emails_to_remove)
      batches = run.each_batch(recipients, max_bcc_at_once) do |users|
        puts "Sending email to #{users.size} users"
        MsrMailer.send_profile_update(users.map(&:email)).deliver_now
      end
      puts "Sent #{batches} groups"
    end
  end
end
