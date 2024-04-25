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
  has_many :shadowing_hours
  has_many :users, through: :staff_spaces
  has_many :staff_spaces
  has_many :space_staff_hour
  has_many :shifts, dependent: :destroy
  has_many :sub_spaces, dependent: :destroy
  has_many :staff_needed_calendars, dependent: :destroy
  has_many :space_manager_joins, dependent: :destroy
  has_many :space_managers, through: :space_manager_joins, source: :user

  after_create :create_popular_hours

  validates :name,
            presence: {
              message: "A name is required for the space"
            },
            uniqueness: {
              message: "Space already exists"
            }

  def signed_in_users
    lab_sessions
      .where("sign_out_time > ?", Time.zone.now)
      .order(sign_out_time: :desc)
      .map(&:user)
      .uniq
  end

  def recently_signed_out_users
    users =
      lab_sessions
        .where("sign_out_time < ?", Time.zone.now)
        .where.not(user: signed_in_users)
        .order(sign_out_time: :asc)
        .last(20)
        .map(&:user)
        .uniq

    users =
      users
        .sort_by do |user|
          user.lab_sessions.where(space: self).last.sign_out_time
        end
        .reverse
    users
  end

  def create_popular_hours
    (0..6).each do |weekday|
      (0..23).each do |hour|
        PopularHour.find_or_create_by(space_id: id, hour: hour, day: weekday)
      end
    end
  end

  def makerspace?
    name.eql?("Makerspace")
  end

  def ceed?
    name.eql?("CEED")
  end

  def jmts?
    name.eql?("JMTS")
  end

  def assigned_color
    colors = [
      [230, 25, 75], # #e6194b
      [60, 180, 75], # #3cb44b
      [255, 225, 25], # #ffe119
      [67, 99, 216], # #4363d8
      [245, 130, 49], # #f58231
      [145, 30, 180], # #911eb4
      [70, 240, 240], # #46f0f0
      [240, 50, 230], # #f032e6
      [128, 128, 0], # #808000
      [0, 128, 128] # #008080
    ]
    colors[id % colors.size]
  end
end
