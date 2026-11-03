class PopularHour < ApplicationRecord
  belongs_to :space, optional: true

  def self.from_space(space_id)
    space = Space.find_by(id: space_id)
    return if space.blank?
    PopularHour.where(space: space).order(day: :asc, hour: :asc)
  end

  # Folds the head count of the hour in progress into the running mean of its (weekday, hour) row, for every
  # space that has people in it. Weekday and hour are read in Time.zone, the same zone the lab session window
  # is cut in, so the row does not depend on the host's clock. Run hourly (config/recurring.yml).
  def self.record_current_hour!(now = Time.zone.now)
    lab_sessions = LabSession.between_dates_picked(now.beginning_of_hour, now.end_of_hour)
    Space.find_each do |space|
      current_users =
        (
          lab_sessions.where(space: space).to_a +
            space.lab_sessions.where("sign_out_time > ?", now).to_a
        ).uniq.count
      next if current_users.zero? # closed now: a zero would drag the mean toward nothing

      popular_hour = find_by(space_id: space.id, hour: now.hour, day: now.wday)
      next if popular_hour.blank?

      new_count = popular_hour.count.next
      popular_hour.update(
        count: new_count,
        mean: ((popular_hour.count * popular_hour.mean) + current_users) / new_count,
        previous_mean: popular_hour.mean
      )
    end
  end

  def self.popular_hours_per_period(start_date, end_date)
    lab_sessions_in_space =
      LabSession.between_dates_picked(
        start_date.beginning_of_day,
        end_date.end_of_day
      )
    data = {}
    Space.all.each do |space|
      data[space.id] = {}
      (0..6).each do |weekday|
        s =
          lab_sessions_in_space.where(
            "extract(dow from created_at) = ?",
            weekday
          ).where(space: space)
        data[space.id][weekday] = {}
        (0..23).each do |hour|
          if (start_date..end_date).count { |date| weekday == date.wday } == 0
            data[space.id][weekday][hour] = 0
          else
            data[space.id][weekday][hour] = (
              s.where("extract('hour' from created_at) = ?", hour).count.to_f /
                (start_date..end_date).count { |date| weekday == date.wday }
            ).round(2)
          end
        end
      end
    end
    data
  end
end
