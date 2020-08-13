# frozen_string_literal: true

namespace :confirmed_users do

  desc 'Set users as confirmed'
  task set_true: :environment do
    User.find_each do |user|
      user.update(confirmed: true)
    end
  end

  desc 'Remind users to confirm their email'
  task remind: :environment do
    User.where(confirmed: false).find_each do |user|
      hash = Rails.application.message_verifier(:user).generate(user.id)
      MsrMailer.confirmation_email(user, hash).deliver_now
    end
  end
end
