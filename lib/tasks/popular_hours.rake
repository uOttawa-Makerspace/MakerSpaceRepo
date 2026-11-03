# frozen_string_literal: true

namespace :popular_hours do
  desc "Calculate the mean of users in the spaces and update popular hours table "
  task calculate_popular_hours: :environment do
    PopularHour.record_current_hour!
  end
end
