# frozen_string_literal: true

require "date"

class Staff::ShiftsScheduleController < StaffAreaController
  include ShiftsDeprecationWarning

  layout "staff_area"

  before_action :set_default_space
  before_action :set_time_period

  def index
    @staff = fetch_staff_members
    @colors = fetch_staff_colors
    @spaces = Space.where(id: StaffSpace.where(user_id: current_user.id).pluck(:space_id))
    @space_id = @user.space_id || Space.first.id
  end

  def get_shifts
    space_id = params[:space_id].present? ? params[:space_id].to_i : @space_id
    start_date = params[:start].present? ? Time.zone.parse(params[:start]) : 3.months.ago
    end_date = params[:end].present? ? Time.zone.parse(params[:end]) : 3.months.from_now
    
    events = Event
      .joins(:event_assignments)
      .where(event_assignments: { user_id: current_user.id })
      .where(event_type: 'shift', space_id: space_id)
      .distinct
      .includes(:training, :course_name, :users)
    
    shifts = events.flat_map do |event|
      event.recurrence_rule.present? ? expand_recurring_event(event, start_date, end_date) : format_event(event, start_date, end_date)
    end.compact
    
    render json: shifts
  end

  private

  def expand_recurring_event(event, range_start, range_end)
    require 'rrule'
    
    rrule_string = event.recurrence_rule.lines.find { |line| line.start_with?('RRULE:') }&.sub('RRULE:', '')&.strip
    return format_event(event, range_start, range_end) unless rrule_string
    
    rrule = RRule::Rule.new(rrule_string, dtstart: event.start_time)
    occurrences = rrule.all(limit: 1000).select { |occ| occ.between?(range_start, range_end) }
    duration = event.end_time - event.start_time
    
    occurrences.map do |occurrence|
      {
        title: event.title.presence || "Shift for #{event.users.map(&:name).join(', ')}",
        start: occurrence,
        end: occurrence + duration,
        color: get_user_color(event.users.first),
        extendedProps: {
          reason: event.description,
          training: event.training&.name_en || "",
          course: event.course_name&.name || "",
          language: event.language
        }
      }
    end
  rescue => e
    Rails.logger.error "Failed to expand event #{event.id}: #{e.message}"
    format_event(event, range_start, range_end)
  end

  def format_event(event, range_start, range_end)
    return [] unless event.start_time.between?(range_start, range_end)
    
    [{
      title: event.title.presence || "Shift for #{event.users.map(&:name).join(', ')}",
      start: event.start_time,
      end: event.end_time,
      color: get_user_color(event.users.first),
      extendedProps: {
        reason: event.description,
        training: event.training&.name_en || "",
        course: event.course_name&.name || "",
        language: event.language
      }
    }]
  end

  def get_user_color(user)
    return "#000000" unless user
    StaffSpace.where(user_id: user.id, space_id: @space_id).pluck(:color).first.presence || "#000000"
  end

  def set_default_space
    @space_id = current_user.space_id || Space.first.id
  end

  def fetch_staff_members
    User.where(id: StaffSpace.where(space_id: @space_id).pluck(:user_id)).pluck(:name, :id)
  end

  def fetch_staff_colors
    StaffSpace
      .where(space_id: @space_id)
      .joins(:user)
      .order("users.name")
      .pluck("users.id", "users.name", :color)
  end

  def set_time_period
    @missing_time_period = false
    if params[:time_period_id] && TimePeriod.find_by(id: params[:time_period_id])
      @time_period = TimePeriod.find(params[:time_period_id])
    else
      date = Date.today
      time_periods = TimePeriod.where("start_date <= ? AND end_date >= ?", date, date)
      @time_period = time_periods.first if time_periods.present?
    end
  end
end