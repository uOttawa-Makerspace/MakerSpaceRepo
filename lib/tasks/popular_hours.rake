# frozen_string_literal: true

namespace :popular_hours do
  desc 'Calculate the mean of users in the spaces and update popular hours table '
  task calculate_popular_hours: :environment do
    hour_start = Time.zone.now.beginning_of_hour
    hour_end = Time.zone.now.end_of_hour
    lab_sessions = LabSession.between_dates_picked(hour_start, hour_end)
    Space.all.each do |space|
      lab_sessions_in_space = lab_sessions.where(space: space)
      lab_sessions_not_logged_out = space.lab_sessions.where('sign_out_time > ?', Time.zone.now)
      current_users = (lab_sessions_in_space + lab_sessions_not_logged_out).uniq.count
      next if current_users == 0 # The space is closed now. So, to avoid the mean being too close to zero.
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
