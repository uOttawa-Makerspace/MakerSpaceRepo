# frozen_string_literal: true

namespace :users_inactive do
  desc "sends emails to a list of emails"
  task check: :environment do
    @users = User.active
    @error_emails = []
    @users.each do |user|
      # Check if user has signed in or tapped in the last year
      if user.last_seen_at.present? && user.last_seen_at < 1.year.ago &&
           user.last_signed_in_time.present? &&
           user.last_signed_in_time < 1.year.ago
        begin
          MsrMailer.send_inactive_email(user).deliver_now
        rescue StandardError => e
          @error_emails << user.email
        end
        user.update(active: false)
      end
    end
    File.open("error_emails.txt", "w") { |f| f.write(@error_emails.join("\r")) }
  end
end
