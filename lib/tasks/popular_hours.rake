# frozen_string_literal: true

namespace :popular_hours do
  desc 'Populate the popular hour table'
  task populate: :environment do
    Space.all.each do |space|
      current_users = space.signed_in_users.count
      day = Time.new.wday
      hour = Time.new.hour
      if PopularHour.where(space_id: space.id, hour: hour, day: day).present?
        popular_hour = PopularHour.where(space_id: space.id, hour: hour, day: day).first
      else
        popular_hour = PopularHour.create(space_id: space.id, hour: hour, day: day, count: 0, mean: 0)
      end
      new_count = popular_hour.count + 1
      mean = ((popular_hour.count*popular_hour.mean) + current_users)/new_count
      popular_hour.update(count: new_count, mean: mean)
    end

    # mean (Number of users)
    # space_id (Space)
    # hour (24h)
    # day (Sunday to Monday)
    # count
  end
end
