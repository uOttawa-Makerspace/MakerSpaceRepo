# frozen_string_literal: true

class Space < ApplicationRecord
  has_many :pi_readers
  has_many :lab_sessions, dependent: :destroy
  has_many :users, through: :lab_sessions
  has_and_belongs_to_many :trainings
  has_many :training_sessions, dependent: :destroy
  has_many :certifications, through: :training_sessions
  has_many :volunteer_tasks, dependent: :destroy
  has_many :popular_hours, dependent: :destroy

  after_create :create_popular_hours

  validates :name, presence: { message: 'A name is required for the space' }, uniqueness: { message: 'Space already exists' }

  def signed_in_users
    lab_sessions.where('sign_out_time > ?', Time.zone.now).reverse.map(&:user).uniq
  end

  def recently_signed_out_users
    users = lab_sessions.where('sign_out_time < ?', Time.zone.now).last(20).map(&:user).uniq
    signed_in_users.each do |user|
      users.delete(user)
    end
    users
  end

  def create_popular_hours
    (0..6).each do |weekday|
      (0..23).each do |hour|
        PopularHour.find_or_create_by(space_id: self.id, hour: hour, day: weekday)
      end
    end
  end
end
