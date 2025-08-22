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
    @spaces =
      Space.all.where(
        id: StaffSpace.where(user_id: current_user.id).pluck(:space_id)
      )
    @space_id = @user.space_id || Space.first.id
  end

  def get_shifts
    shifts =
      Shift
        .includes(:users)
        .where(
          pending: false,
          users: {
            id: StaffSpace.where(space_id: @space_id).pluck(:user_id)
          },
          space_id: @space_id
        )
        .map { |shift| shift_to_event(shift) }
    render json: shifts
  end

  private

  def set_default_space
    @space_id = current_user.space_id || Space.first.id
  end

  def fetch_staff_members
    User.where(id: StaffSpace.where(space_id: @space_id).pluck(:user_id)).pluck(
      :name,
      :id
    )
  end

  def fetch_staff_colors
    StaffSpace
      .where(space_id: @space_id)
      .joins(:user)
      .order("users.name")
      .pluck("users.id", "users.name", :color)
  end

  def shift_to_event(shift)
    user_color = get_user_color(shift.users.first)

    {
      title: shift.return_event_title,
      start: shift.start_datetime,
      end: shift.end_datetime,
      color: user_color,
      extendedProps: {
        reason: shift.reason,
        training: shift.training.present? ? shift.training.name_en : "",
        course: shift.course,
        language: shift.language
      }
    }
  end

  def get_user_color(user)
    color =
      StaffSpace
        .where(user_id: user.id, space_id: @space_id)
        .pluck(:color)
        .first
    color.presence || "#000000"
  end

  def set_time_period
    @missing_time_period = false
    if params[:time_period_id] &&
         TimePeriod.find_by(id: params[:time_period_id])
      @time_period = TimePeriod.find(params[:time_period_id])
    else
      date = Date.today
      time_periods =
        TimePeriod.where("start_date <= ? AND end_date >= ?", date, date)
      @time_period = time_periods.first if time_periods.present?
    end
  end
end
