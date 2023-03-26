# frozen_string_literal: true

class LabSession < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :space, optional: true

  scope :between_dates_picked,
        ->(start_date, end_date) {
          where("created_at BETWEEN ? AND ? ", start_date, end_date)
        }

  def self.to_csv(attributes)
    CSV.generate { |csv| attributes.each { |row| csv << row } }
  end
end
