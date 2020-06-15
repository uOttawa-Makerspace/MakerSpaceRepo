# frozen_string_literal: true

namespace :emails do
  desc 'Send email survey'
  task send_survey_ceed: :environment do
    User.active.find_each do |u|
      MsrMailer.send_survey_ceed(u.email).deliver_now
    end
  end
end
