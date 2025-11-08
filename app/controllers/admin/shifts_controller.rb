# frozen_string_literal: true

class Admin::ShiftsController < AdminAreaController
  include ShiftsDeprecationWarning

  before_action :set_default_space
  before_action :set_shifts, only: %i[edit update destroy]
  before_action :set_time_period

  def index
    @staff =
      User
        .staff
        .where(id: StaffSpace.where(space_id: @space_id).pluck(:user_id))
        .order("LOWER(name) ASC")
        .pluck(:name, :id)
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @space_id = @user.space_id || Space.first.id
    @colors = []

    StaffSpace
      .joins(:user)
      .where(space_id: @space_id)
      .merge(
        User.staff
      ) # NOTE: why isn't this the default scope? Ask Alex *again* sometime later lol
      .order("users.name")
      .each do |staff|
        @colors << { user: staff.user, color: staff.color } if !staff.nil? && !staff.user.nil?
      end
  end

  def shifts
    @staff =
      User
        .staff
        .where(id: StaffSpace.where(space_id: @space_id).pluck(:user_id))
        .order("LOWER(name) ASC")
        .pluck(:name, :id)
    @spaces = Space.all.where(id: SpaceStaffHour.all.pluck(:space_id))
    @colors = []

    StaffSpace
      .joins(:user)
      .where(space_id: @space_id)
      .merge(User.staff)
      .order("users.name")
      .each do |staff|
        next unless !staff.nil? && !staff.user.nil? && !staff.user_id.nil?
        @colors << {
          id: staff.user.id,
          name: staff.user.name,
          color: staff.color
        }
      end

    @pending_shifts = Shift.where(space_id: @user.space_id, pending: true)
  end

  def pending_shifts
    @pending_shifts = Shift.where(space_id: @user.space_id, pending: true)
    render partial: "admin/shifts/pending_shifts"
  end

  def confirm_shifts
    if params[:shift_ids]
      Shift.where(id: params[:shift_ids], space_id: @user.space_id).update_all(
        pending: false
      )
    end
    redirect_to shifts_admin_shifts_path,
                notice: "Selected shifts have been successfully confirmed!"
  end

  def clear_pending_shifts
    Shift.where(space_id: @user.space_id, pending: true).destroy_all
    redirect_to shifts_admin_shifts_path,
                notice: "Shifts have been successfully cleared!"
  end

  def confirm_current_week_shifts
    end_of_week_param = Time.zone.parse(params[:end_of_week])
    start_of_week = end_of_week_param.beginning_of_week - 1.day
    end_of_week = end_of_week_param.end_of_week - 1.day

    Shift.where(
      space_id: @user.space_id,
      pending: true,
      start_datetime: start_of_week..end_of_week
    ).update(pending: false)

    render json: { status: "ok" }
  end

  def create
    # calendar events are emailed and synced with google calendar
    # on model save, see models/shifts.rb
    if params[:shift].present? && params[:user_id].present?
      @shift = Shift.new(shift_params.merge(space_id: @space_id))
      params[:user_id].each { |user_id| @shift.users << User.find(user_id) }
    elsif params[:start_datetime].present? &&
          params[:start_datetime].present? && params[:user_id].present?
      start_date = Time.zone.parse(params[:start_datetime])
      end_date = Time.zone.parse(params[:start_datetime])
      @shift =
        Shift.new(
          space_id: @space_id,
          start_datetime: start_date,
          end_datetime: end_date,
          reason: params[:reason]
        )
      @shift.users << User.where(id: params[:user_id])
    else
      render json: { error: "Missing params" }, status: :unprocessable_entity
      return
    end

    respond_to do |format|
      if @shift.save
        format.html do
          redirect_to shifts_admin_shifts_path,
                      notice: "The shift has been successfully created."
        end
        format.json do
          render json: {
                   id: @shift.id,
                   name: @shift.return_event_title,
                   color: @shift.color(@space_id, @shift.pending? ? 0.7 : 1),
                   start: @shift.start_datetime,
                   end: @shift.end_datetime,
                   extendedProps: {
                     reason: @shift.reason,
                     training:
                       @shift.training.present? ? @shift.training.name : "",
                     course: @shift.course,
                     language: @shift.language
                   },
                   className:
                     @shift.users.first.name.strip.downcase.gsub(" ", "-")
                 }
        end
      else
        format.html { render :new }
        format.json do
          render json: @shift.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def copy_to_next_week
    end_of_week_param = Time.zone.parse(params[:end_of_week])
    start_of_week = end_of_week_param.beginning_of_week - 1.day
    end_of_week = end_of_week_param.end_of_week - 1.day
    new_shifts = []
    Shift
      .where(space_id: @space_id, start_datetime: start_of_week..end_of_week)
      .each do |shift|
        new_start = shift.start_datetime + 1.week
        new_end = shift.end_datetime + 1.week
        new_shift =
          Shift.create(
            space_id: @space_id,
            start_datetime: new_start,
            end_datetime: new_end,
            reason: shift.reason,
            pending: true
          )
        shift.users.each { |user| new_shift.users << user }
        if !new_shift.save
          new_shifts.each(&:destroy)
          redirect_to shifts_admin_shifts_path,
                      alert: "There was an error copying shifts."

          return
        else
          new_shifts << new_shift
        end
      end
    render json: { status: "ok" }
  end

  def update
    if params[:shift].present?
      respond_to do |format|
        if @shift.update(shift_params)
          format.html do
            redirect_to shifts_admin_shifts_path,
                        notice: "The shift has been successfully updated."
          end
          format.json { render json: { status: "ok" } }
        else
          format.html { render :edit }
          format.json do
            render json: @shift.errors, status: :unprocessable_entity
          end
        end
      end
    elsif params[:start_datetime].present? && params[:end_datetime].present?
      start_date = Time.zone.parse(params[:start_datetime])
      end_date = Time.zone.parse(params[:end_datetime])

      respond_to do |format|
        if @shift.update(start_time: start_date, end_time: end_date)
          format.html do
            redirect_to shifts_admin_shifts_path,
                        notice: "The shift has been successfully updated."
          end
          format.json { render json: { status: "ok" }, status: :ok }
        else
          format.html { render :edit }
          format.json do
            render json: @shift.errors, status: :unprocessable_entity
          end
        end
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.json do
          render json: {
                   error: "Missing params"
                 },
                 status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @shift.destroy
    respond_to do |format|
      format.html do
        redirect_to staff_availabilities_path,
                    notice: "The shift has been successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def update_color
    if params[:user_id].present? &&
         StaffSpace.where(
           user_id: params[:user_id],
           space_id: @user.space_id
         ).present? && params[:color].present?
      staff_space =
        StaffSpace.where(
          user_id: params[:user_id],
          space_id: @user.space_id
        ).first
      if staff_space.update(color: params[:color])
        flash[:notice] = "Color updated successfully"
      else
        flash[:alert] = "Color could not be updated"
      end
    else
      flash[:alert] = "An error occurred, try again later."
    end
    respond_to do |format|
      format.html do
        redirect_to(
          (
            if params[:shifts].present?
              shifts_admin_shifts_path
            else
              admin_shifts_path
            end
          )
        )
      end
      format.json { render json: { status: :ok } }
    end
  end

  def get_availabilities
    opacity = params[:transparent].present? ? 0.25 : 1
    staff_availabilities = []
    @space_id = params[:space_id] if params[:space_id].present?
    StaffAvailability
      .includes(:user, :exceptions)
      .includes(user: :staff_spaces)
      .where(
        user_id: StaffSpace.where(space_id: @space_id).pluck(:user_id),
        time_period: @time_period
      )
      .all
      .each do |sa|
        event = {}
        event[
          "title"
        ] = "#{sa.user.name} is unavailable (#{sa.recurring? ? "Recurring" : "One-Time"})"
        event["id"] = sa.id

        event["daysOfWeek"] = [sa.day]
        event["startTime"] = (sa.start_time || sa.start_datetime).strftime(
          "%H:%M"
        )
        event["endTime"] = (sa.end_time || sa.end_datetime).strftime("%H:%M")
        event["startRecur"] = (
          sa.start_datetime || sa.time_period.start_date
        ).beginning_of_day
        event["endRecur"] = (
          sa.end_datetime || sa.time_period.end_date
        ).end_of_day

        event["color"] = hex_color_to_rgba(
          sa.user.staff_spaces.find_by(space_id: @space_id).color,
          opacity
        )
        event["recurring"] = sa.recurring?
        event["userId"] = sa.user.id
        event["className"] = sa.user.name.strip.downcase.gsub(" ", "-")
        event["exceptions"] = sa.exceptions || false
        staff_availabilities << event
      end

    render json: staff_availabilities
  end

  def get_shifts
    shifts = []

    Shift
      .includes(users: :staff_spaces)
      .includes(:space, :training)
      .where(
        "users.id": StaffSpace.where(space_id: @space_id).pluck(:user_id),
        space_id: @space_id
      )
      .where(start_datetime: (params[:start]..params[:end]))
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
  end

  def get_staff_needed
    staff_needed = []

    SpaceStaffHour
      .where(space_id: @space_id)
      .each do |shift|
        title = ""
        title = shift.training_level_id.nil? ? "Staff Needed" : "Staff Needed - #{TrainingLevel.find(shift.training_level_id).name}"
        if shift.course_name_id.nil?
  title = "Staff Needed"
else
  title +=
            " - #{CourseName.find(shift.course_name_id).name} - #{shift.language}"
end
        event = {}
        event["title"] = title
        event["daysOfWeek"] = [shift.day]
        event["startTime"] = shift.start_time.strftime("%H:%M")
        event["endTime"] = shift.end_time.strftime("%H:%M")
        staff_needed << event
      end

    render json: staff_needed
  end

  def get_external_staff_needed
    render json:
             StaffNeededCalendar.where(space_id: @space_id).as_json(
               only: %i[calendar_url color id]
             )
  end

  def get_users_hours_between_dates
    unless params[:start_date].present? && params[:end_date].present?
      render json: { error: "Missing start_date or end_date" }, status: :unprocessable_entity and
        return
    end

    hours = {}
    StaffSpace
      .includes(:user)
      .where(space_id: @space_id)
      .each { |ss| hours[ss.user_id] = 0 }

    Shift
      .includes(:users)
      .where(
        space_id: @space_id,
        start_datetime:
          Time.zone.parse(params[:start_date])..Time.zone.parse(
            params[:end_date]
          )
      )
      .each do |shift|
        duration = (shift.end_datetime - shift.start_datetime) / 3600
        shift.users.each { |u| hours[u.id] = hours[u.id] + duration }
      end

    render json: hours.as_json
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
  def shift_suggestions
    weekday = params[:day]
    start_time = params[:start]
    end_time = params[:end]
    time_period_id = params[:time_period_id]

    shift_start_date = Time.zone.parse(start_time).strftime("%Y%m%d%H%M").to_i
    shift_end_date = Time.zone.parse(end_time).strftime("%Y%m%d%H%M").to_i
    shift_start_time = Time.zone.parse(start_time).strftime("%H%M").to_i
    shift_end_time = Time.zone.parse(end_time).strftime("%H%M").to_i

    time_period_id = @time_period.id if time_period_id.nil?

    @suggestions = []
    @excluded = []

    StaffSpace
      .where(space_id: @space_id)
      .find_each do |staff|
        next unless !staff.nil? && !staff.user.nil? && !staff.user_id.nil?
        next unless staff.user.staff? # suggest active staff only
        recurring_query =
          staff.user.staff_availabilities.where(
            time_period_id: time_period_id,
            recurring: true,
            day: weekday
          )
        one_time_query =
          staff.user.staff_availabilities.where(
            time_period_id: time_period_id,
            recurring: false
          )

        recurring_query.each do |availability|
          availability_start_time =
            availability.start_time.strftime("%H%M").to_i
          availability_end_time = availability.end_time.strftime("%H%M").to_i
          if (
               availability_start_time <= shift_start_time &&
                 availability_end_time <= shift_start_time
             ) ||
               (
                 availability_start_time >= shift_end_time &&
                   availability_end_time >= shift_end_time
               )
            unless @suggestions.include?(staff.user) ||
                     @excluded.include?(staff.user)
              @suggestions << staff.user
            end
          else
            @excluded << staff.user unless @excluded.include?(staff.user)
          end
        end

        one_time_query.each do |availability|
          availability_start_date =
            availability.start_datetime.strftime("%Y%m%d%H%M").to_i
          availability_end_date =
            availability.end_datetime.strftime("%Y%m%d%H%M").to_i

          if (
               availability_start_date <= shift_start_date &&
                 availability_end_date <= shift_start_date
             ) ||
               (
                 availability_start_date >= shift_end_date &&
                   availability_end_date >= shift_end_date
               )
            unless @suggestions.include?(staff.user) ||
                     @excluded.include?(staff.user)
              @suggestions << staff.user
            end
          else
            @excluded << staff.user unless @excluded.include?(staff.user)
          end
        end

        @suggestions << staff.user if recurring_query.empty? && one_time_query.empty?
      end
    render json:
             @suggestions
               .filter { |user| !@excluded.include?(user) }
               .reduce([]) { |arr, user|
                 arr << { id: user.id, name: user.name, acceptable: true }
               } +
               @excluded.reduce([]) { |arr, user|
                 arr << { id: user.id, name: user.name, acceptable: false }
               }
  end

  private

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end

  def set_default_space
    @space_id = @user.space_id || Space.first.id
  end

  def set_shifts
    @shift = Shift.find(params[:id])
  end

  def shift_params
    params.require(:shift).permit(
      :start_datetime,
      :end_datetime,
      :reason,
      :space_id,
      :training_id,
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
