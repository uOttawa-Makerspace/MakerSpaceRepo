# frozen_string_literal: true

namespace :popular_hours do
  desc 'Calculate the mean of users in the spaces and update popular hours table '
  task calculate_popular_hours: :environment do
    Space.all.each do |space|
      current_users = space.signed_in_users.count
      day = Time.new.wday
      hour = Time.new.hour
      popular_hour = PopularHour.find_by(space_id: space.id, hour: hour, day: day)
      next if popular_hour.blank?
      new_count = popular_hour.count.next
      mean = ((popular_hour.count*popular_hour.mean) + current_users)/new_count
      popular_hour.update(count: new_count, mean: mean)
    end
  end
end
