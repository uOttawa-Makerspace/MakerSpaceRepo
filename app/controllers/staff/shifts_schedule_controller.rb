# frozen_string_literal: true
require "date"
class Staff::ShiftsScheduleController < StaffAreaController
  layout "staff_area"

  before_action :set_default_space
  before_action :set_time_period

  def index
    @staff =
      User.where(
        id: StaffSpace.where(space_id: @space_id).pluck(:user_id)
      ).pluck(:name, :id)
    @spaces =
      Space.joins(:staff_spaces).where(
        staff_spaces: {
          user_id: current_user.id
        }
      )
    @colors = []

    StaffSpace
      .joins(:user)
      .where(space_id: @space_id)
      .order("users.name")
      .each do |staff|
        @colors << {
          id: staff.user.id,
          name: staff.user.name,
          color: staff.color
        }
      end
  end

  def shifts
    @staff =
      User.where(
        id: StaffSpace.where(space_id: @space_id).pluck(:user_id)
      ).pluck(:name, :id)
    @spaces =
      Space.joins(:staff_spaces).where(
        staff_spaces: {
          user_id: current_user.id
        }
      )
    @colors = []

    StaffSpace
      .joins(:user)
      .where(space_id: @space_id)
      .order("users.name")
      .each do |staff|
        @colors << {
          id: staff.user.id,
          name: staff.user.name,
          color: staff.color
        }
      end
  end

  def get_shifts
    shifts = []

    Shift
      .includes(:users)
      .where(users: { id: current_user.id }, space_id: @space_id)
      .each do |shift|
        event = {}
        event["title"] = shift.return_event_title
        event["extendedProps"] = {
          reason: shift.reason,
          training: shift.training.present? ? shift.training.name : "",
          course: shift.course,
          language: shift.language,
          color: shift.color(@space_id, (shift.pending? ? 0.7 : 1))
        }
        event["id"] = shift.id
        event["start"] = shift.start_datetime
        event["end"] = shift.end_datetime
        event["color"] = shift.color(@space_id, (shift.pending? ? 0.7 : 1))
        event["className"] = "user-#{shift.users.first.id}"
        shifts << event
      end

    render json: shifts
  end

  def get_shift
    shift = Shift.find(params[:id])

    if shift.users.include?(current_user)
      render json: {
               **shift.as_json,
               extendedProps: {
                 reason: shift.reason,
                 training: shift.training.present? ? shift.training.name : "",
                 course: shift.course,
                 language: shift.language
               },
               users: shift.users.map { |u| { id: u.id, name: u.name } }
             }
    else
      redirect_to some_path, alert: "You are not authorized to view this shift."
    end
  end

  def ics
    if params[:staff_needed_calendar_id].present? &&
         StaffNeededCalendar.where(
           id: params[:staff_needed_calendar_id]
         ).present?
      snc = StaffNeededCalendar.find(params[:staff_needed_calendar_id])
      ics_file = URI.open(snc.calendar_url).read
      send_data(ics_file, filename: "snc_#{snc.id}.ics", type: "text/calendar")
    end
  end

  private

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end

  def set_default_space
    @space_id = @user.space_id || Space.first.id
  end

  def shift_params
    params.require(:shift).permit(
      :start_datetime,
      :end_datetime,
      :space_id,
      :language,
      :course,
      user_id: []
    )
  end

  def set_time_period
    @missing_time_period = false
    if params[:time_period_id] &&
         TimePeriod.find(params[:time_period_id]).present?
      @time_period = TimePeriod.find(params[:time_period_id])
    else
      date = Date.today
      time_periods =
        TimePeriod.where("start_date <= ? AND end_date >= ?", date, date)
      if time_periods.present?
        @time_period = time_periods.first
      else
        @missing_time_period = true
      end
    end
  end
end
