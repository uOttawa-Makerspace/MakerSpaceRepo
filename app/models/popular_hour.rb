class PopularHour < ApplicationRecord
  belongs_to :space

  def self.from_space(space_id)
    space = Space.find_by(id: space_id)
    return if space.blank?
    PopularHour.where(space: space).order(day: :asc, hour: :asc)
  end

  def self.popular_hours_per_period(start_date, end_date)
    lab_sessions_in_space = LabSession.between_dates_picked(start_date.beginning_of_day, end_date.end_of_day)
    data = {}
    Space.all.each do |space|
      data[space.id] = {}
      (0..6).each do |weekday|
        s = lab_sessions_in_space.where("extract(dow from created_at) = ?", weekday).where(space: space)
        data[space.id][weekday] = {}
        (0..23).each do |hour|
          if (start_date..end_date).count {|date| weekday == date.wday } == 0
            data[space.id][weekday][hour] = 0
          else
            data[space.id][weekday][hour] = (s.where("extract('hour' from created_at) = ?", hour).count.to_f / (start_date..end_date).count {|date| weekday == date.wday }).round(2)
          end
        end
      end
    end
    data
  end
end
