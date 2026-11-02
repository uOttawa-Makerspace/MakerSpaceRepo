# frozen_string_literal: true

namespace :confirmed_users do
  desc "Set users as confirmed"
  task set_true: :environment do
    User.find_each { |user| user.update(confirmed: true) }
  end

  desc "Remind users to confirm their email"
  task remind: :environment do
    User
      .where(confirmed: false)
      .find_each do |user|
        hash = user.generate_token_for(:email_confirmation)
        MsrMailer.confirmation_email(user, hash).deliver_now
      end
  end
end
