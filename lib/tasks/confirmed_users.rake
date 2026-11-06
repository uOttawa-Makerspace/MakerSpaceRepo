# frozen_string_literal: true

namespace :confirmed_users do
  # Mails every unconfirmed, not deactivated user once per day. A second run on the same day mails nobody, an interrupted run
  # continues where it stopped, and FORCE=1 mails everyone again.
  desc "Remind users to confirm their email"
  task remind: :environment do
    run = BulkMailRun.new("confirmed_users_remind", Time.zone.today.iso8601, force: ENV["FORCE"] == "1")
    if run.done?
      puts "Reminders were already sent today; run with FORCE=1 to send them again."
    else
      mailed = run.each_user(User.where(confirmed: false).not_deactivated) do |user|
        hash = user.generate_token_for(:email_confirmation)
        MsrMailer.confirmation_email(user, hash).deliver_now
      end
      puts "Reminded #{mailed} users"
    end
  end
end
