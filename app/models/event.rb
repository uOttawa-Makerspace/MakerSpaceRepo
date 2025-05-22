require 'ice_cube'

class Event < ApplicationRecord
  belongs_to :created_by, class_name: 'User'
  belongs_to :space
  has_many :event_assignments, dependent: :destroy
  has_many :users, through: :event_assignments, source: :user

  validates :title, :start_time, :end_time, presence: true
  validate :end_time_after_start_time

  private

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?

    return unless end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    
  end
end