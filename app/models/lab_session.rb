# frozen_string_literal: true

class LabSession < ApplicationRecord
  belongs_to :user
  belongs_to :space

  scope :between_dates_picked, ->(start_date, end_date) { where('created_at BETWEEN ? AND ? ', start_date, end_date) }

  def self.to_csv(attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

  def self.get_popular_hours_per_period(start_date, end_date, space_id)
    sessions = LabSession.where(space_id: space_id).between_dates_picked(start_date, end_date)
    mean = {}
    (0..6).each do |weekday|
      s = sessions.where("extract(dow from created_at) = ?", weekday)
      mean[weekday] = {}
      (0..23).each do |hour|
        if (start_date..end_date).count {|date| (weekday..weekday).include?(date.wday) } == 0
          mean[weekday][hour] = 0
        else
          mean[weekday][hour] = s.where("extract('hour' from created_at) = ?", hour).count / (start_date..end_date).count {|date| (weekday..weekday).include?(date.wday) }
        end
      end
    end
    mean
  end
end
