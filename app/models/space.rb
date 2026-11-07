# frozen_string_literal: true

class Space < ApplicationRecord
  include CalendarHelper

  has_many :pi_readers
  has_many :keys, dependent: :nullify
  has_many :key_requests, dependent: :nullify
  has_many :walk_in_safety_sheets
  has_many :lab_sessions
  has_many :users, through: :lab_sessions
  has_and_belongs_to_many :trainings
  has_many :training_sessions
  has_many :certifications, through: :training_sessions
  has_many :volunteer_tasks
  has_many :popular_hours, dependent: :destroy
  has_many :shadowing_hours
  has_many :users, dependent: :nullify
  has_many :staff_spaces, dependent: :destroy
  has_many :space_staff_hour
  has_many :shifts, dependent: :destroy
  has_many :sub_spaces, dependent: :destroy
  has_many :sub_space_bookings, through: :sub_spaces
  has_many :staff_needed_calendars, dependent: :destroy
  has_many :space_manager_joins, dependent: :destroy
  has_many :space_managers, through: :space_manager_joins, source: :user
  has_many :users, through: :staff_spaces

  # A space with user history cannot be deleted: walk-in safety sheets, lab sessions, training sessions (with
  # their certifications and exams), volunteer tasks (with their hours) and sub space bookings feed reports and
  # course records. The delete is refused with an explanation instead. The check runs before anything is
  # destroyed (prepend), so the sub spaces are not taken along with their bookings.
  HISTORY_ASSOCIATIONS = %i[walk_in_safety_sheets lab_sessions training_sessions volunteer_tasks sub_space_bookings].freeze
  REFUSAL_KEY = :"restrict_dependent_destroy.has_many"
  before_destroy :refuse_deletion_while_history_exists, prepend: true

  after_create :create_popular_hours, unless: -> { Rails.env.test? }

  validates :name,
            presence: {
              message: "A name is required for the space"
            },
            uniqueness: {
              message: "Space already exists"
            }

  # The history this space still has, as the associations that block its deletion. Empty when it can be deleted.
  def blocking_history
    HISTORY_ASSOCIATIONS.select { |association| public_send(association).exists? }
  end

  # Why this space cannot be deleted, one message per kind of history, built the way restrict_with_error builds its
  # message (the same key and association names, so model-scoped overrides and the locale apply).
  def deletion_refusals
    blocking_history.map { |association| errors.generate_message(:base, REFUSAL_KEY, record: refusal_record_name(association)) }
  end

  # Visits keep their user after the account is soft-deleted, so the rosters below leave deleted
  # users out explicitly: they are not listed as in, or recently in, a space. The join reads the
  # user's deleted flag in the same query (the association itself reaches deleted users).
  def signed_in_users
    visible_lab_sessions
      .where("sign_out_time > ?", Time.zone.now)
      .order(sign_out_time: :desc)
      .map(&:user)
      .uniq
  end

  # For tables that show each user's previous visit.
  def signed_in_users_with_history
    with_visit_history(signed_in_users)
  end

  def recently_signed_out_users
    users =
      visible_lab_sessions
        .where("sign_out_time < ?", Time.zone.now)
        .where.not(user_id: lab_sessions.where("sign_out_time > ?", Time.zone.now).where.not(user_id: nil).select(:user_id))
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

  # For tables that show each user's previous visit.
  def recently_signed_out_users_with_history
    with_visit_history(recently_signed_out_users)
  end

  def visible_lab_sessions
    lab_sessions.includes(:user).where(users: { deleted: false })
  end
  private :visible_lab_sessions

  # The dashboard rows show each user's previous visit; load what they read in one go.
  def with_visit_history(users)
    ActiveRecord::Associations::Preloader.new(
      records: users,
      associations: [:lab_sessions]
    ).call
    users
  end
  private :with_visit_history

    def create_popular_hours
      # Optimization: Prepare data in memory
      records = []
      (0..6).each do |weekday|
        (0..23).each do |hour|
          records << { space_id: id, hour: hour, day: weekday, created_at: Time.current, updated_at: Time.current }
        end
      end
      
      # Single SQL Insert
      PopularHour.insert_all(records)
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

    # logger.warn "Events: #{events.inspect}"

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

    # logger.warn "WE: #{weekly_events.inspect}"

    weekly_events.sort_by(&:dtstart)
  end

  private

  def refusal_record_name(association)
    self.class.human_attribute_name(association).downcase
  end

  def refuse_deletion_while_history_exists
    history = blocking_history
    return if history.empty?

    history.each { |association| errors.add(:base, REFUSAL_KEY, record: refusal_record_name(association)) }
    throw :abort
  end
end
