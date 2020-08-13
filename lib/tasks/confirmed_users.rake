# frozen_string_literal: true

namespace :confirmed_users do
  desc 'Set users as confirmed'
  task set_true: :environment do
    User.find_each do |user|
      user.update(confirmed: true)
    end
  end
end
