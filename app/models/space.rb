# frozen_string_literal: true

class Space < ApplicationRecord
  include CalendarHelper

  has_many :pi_readers
  has_many :lab_sessions, dependent: :destroy
  has_many :users, through: :lab_sessions
  has_and_belongs_to_many :trainings
  has_many :training_sessions, dependent: :destroy
  has_many :certifications, through: :training_sessions
  has_many :volunteer_tasks, dependent: :destroy
  has_many :popular_hours, dependent: :destroy
  has_many :shadowing_hours
  has_many :users
  has_many :staff_spaces
  has_many :space_staff_hour
  has_many :shifts, dependent: :destroy
  has_many :sub_spaces, dependent: :destroy
  has_many :staff_needed_calendars, dependent: :destroy
  has_many :space_manager_joins, dependent: :destroy
  has_many :space_managers, through: :space_manager_joins, source: :user
  has_many :users, through: :staff_spaces

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
      .includes(:user)
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

    users
        .sort_by do |user|
          user.lab_sessions.where(space: self).last.sign_out_time
        end
        .reverse
    
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

  # FIXME: This should be a checkbox somewhere
  def needs_walk_in_safety_sheet?
    name.eql?("Brunsfield Centre") || name.eql?("MTC")
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

  def weekly_open_hours
    calendar = staff_needed_calendars.find_by(role: "open_hours")
    return [] if calendar.blank?

    parsed = parse_ics_calendar(calendar.calendar_url, name: "Open Hours")
    return [] if parsed.blank?

    events = parsed.first[:events]

    start_of_week = Time.zone.today.beginning_of_week(start_day = :saturday).beginning_of_day
    end_of_week   = Time.zone.today.end_of_week(start_day = :saturday).end_of_day

    weekly_events = []

    events.each do |ev|
      next if ev[:start].blank?

      dtstart = Time.zone.parse(ev[:start])
      dtend =
        if ev[:end].present?
          Time.zone.parse(ev[:end])
        elsif ev[:duration].present?
          dtstart + (ev[:duration].to_f / 1000.0)
        else
          dtstart + 1.hour
        end
      
      if ev[:rrule].present?
        rule_obj = ev[:rrule]
        
        rule = case rule_obj[:freq]&.upcase
              when "DAILY"   then IceCube::Rule.daily
              when "WEEKLY"  then IceCube::Rule.weekly
              when "MONTHLY" then IceCube::Rule.monthly
              when "YEARLY"  then IceCube::Rule.yearly
              end

              next if rule.nil?
              
        if rule_obj[:byweekday].present?
          weekday_map = {
            "su" => 0,
            "mo" => 1,
            "tu" => 2,
            "we" => 3,
            "th" => 4,
            "fr" => 5,
            "sa" => 6
          }

          mapped_days = rule_obj[:byweekday].map { |d| weekday_map[d] }.compact

          rule.day(*mapped_days) if mapped_days.any?
        end
        
        rule.until(Time.zone.parse(rule_obj[:until])) if rule_obj[:until].present?
        rule.count(rule_obj[:count]) if rule_obj[:count].present?

        schedule = IceCube::Schedule.new(dtstart, end_time: dtend)
        schedule.add_recurrence_rule(rule)

        if ev[:exdate].present?
          ev[:exdate].each do |ex|
              schedule.add_exception_time(Time.zone.parse(ex))
            rescue StandardError
              next
          end
        end

        occurrences = schedule.occurrences_between(start_of_week, end_of_week)
        occurrences.each do |occ|
          occ_start = occ.start_time.in_time_zone
          occ_end   = begin
                        occ.end_time.in_time_zone
                      rescue StandardError
                        (occ_start + (dtend - dtstart))
                      end

          weekly_events << OpenStruct.new(
            dtstart: occ_start,
            dtend: occ_end,
            title: ev[:title]
          )
        end

      elsif dtstart >= start_of_week && dtstart <= end_of_week
        weekly_events << OpenStruct.new(
          dtstart: dtstart,
          dtend: dtend,
          title: ev[:title]
        )
      end
    end

    weekly_events.sort_by(&:dtstart)
  end

end
