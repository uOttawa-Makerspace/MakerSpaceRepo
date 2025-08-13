class StaffAvailabilitiesController < ApplicationController
  include ShiftsDeprecationWarning

  before_action :check_admin_or_staff_in_space
  before_action :set_staff_availabilities, only: %i[edit update destroy]
  before_action :set_selected_user
  before_action :set_time_period

  def index
    @user_availabilities =
      @selected_user
        .staff_availabilities
        .where(time_period: @time_period)
        .order(:day, :start_time)
    @staff_availabilities =
      StaffAvailability
        .all
        .where(time_period: @time_period)
        .order(:user_id, :day, :start_time) if @user.admin?
  end

  def get_availabilities
    staff_availabilities = []
    @selected_user
      .staff_availabilities
      .where(time_period: @time_period)
      .each do |a|
        event = {}
        event[
          "title"
        ] = "#{a.user.name} is unavailable (#{a.recurring? ? "Recurring" : "One-Time"})"
        event["id"] = a.id
        event["daysOfWeek"] = [a.day]
        event["startTime"] = (a.start_time || a.start_datetime).strftime(
          "%H:%M"
        )
        event["endTime"] = (a.end_time || a.end_datetime).strftime("%H:%M")
        event["startRecur"] = (
          a.start_datetime || a.time_period.start_date
        ).beginning_of_day
        event["endRecur"] = (
          a.end_datetime || a.time_period.end_date
        ).end_of_day
        event["recurring"] = a.recurring?
        event["exceptions"] = a.exceptions || false
        staff_availabilities << event
      end

    render json: staff_availabilities
  end

  def new
    @staff_availability = StaffAvailability.new
    @staffs = User.all.where(id: StaffSpace.all.map(&:user_id).uniq)
    @time_periods = TimePeriod.all
  end

  def edit
    @date_display = @staff_availability.recurring? ? "none" : "block"
    @staffs = User.all.where(id: StaffSpace.all.map(&:user_id).uniq)
    @time_periods = TimePeriod.all
  end

  def create
    if params[:staff_availability][:time_period_id].present? ||
         @time_period.present?
      time_period_id =
        params[:staff_availability][:time_period_id].presence || @time_period.id
    elsif params[:time_period_id].present? || @time_period.present?
      time_period_id =
        params[:time_period_id].presence || @time_period.id
    end

    # From staff availability form
    # FIXME converge this if statement into one
    if params[:start_date].present? && params[:end_date].present? &&
         time_period_id.present?
      params_start_time = Time.parse(params[:staff_availability][:start_time])
      params_end_time = Time.parse(params[:staff_availability][:end_time])
      params_start_date = Date.parse(params[:start_date])
      params_end_date = Date.parse(params[:end_date])

      @staff_availability =
        StaffAvailability.new(
          user_id: @selected_user.id,
          start_datetime:
            params_start_date +
              params_start_time.seconds_since_midnight.seconds,
          end_datetime:
            params_end_date + params_end_time.seconds_since_midnight.seconds,
          time_period_id: time_period_id,
          recurring: params[:staff_availability][:recurring].to_i.zero?,
          day: params_start_date.wday,
          start_time: params_start_time.strftime("%H:%M"),
          end_time: params_end_time.strftime("%H:%M")
        )
      # From admin area unavailability form
    elsif params[:staff_availability].present? && time_period_id.present?
      params_start_time =
        Time.zone.parse(params[:staff_availability][:start_time])
      params_end_time = Time.zone.parse(params[:staff_availability][:end_time])
      params_start_date =
        begin
          Date.parse(params[:staff_availability][:start_date])
        rescue StandardError
          @time_period.start_date
        end
      params_end_date =
        begin
          Date.parse(params[:staff_availability][:end_date])
        rescue StandardError
          @time_period.end_date
        end
      # Remove start_date and end_date in all cases
      # we convert those to datetime objects
      @staff_availability =
        StaffAvailability.new(
          staff_availability_params.except(:start_date, :end_date).merge(
            # For single-time: set start and end of unavailability as datetime
            # For recurring: set datetime when to start and stop recurring
            start_datetime:
              params_start_date +
                params_start_time.seconds_since_midnight.seconds,
            end_datetime:
              params_end_date + params_end_time.seconds_since_midnight.seconds,
            user_id: @selected_user.id,
            time_period_id: time_period_id
          )
        )
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

    time_period = TimePeriod.find(time_period_id)

    respond_to do |format|
      if @staff_availability.save!
        format.html do
          redirect_to staff_availabilities_path,
                      notice:
                        "The staff unavailabilities were successfully created."
        end
        format.json do
          render json: {
                   title:
                     "#{@staff_availability.user.name} is unavailable (#{@staff_availability.recurring? ? "Recurring" : "One-Time"})",
                   daysOfWeek: [@staff_availability.day],
                   startTime:
                     (
                       if @staff_availability.recurring?
                         @staff_availability.start_time.strftime("%H:%M")
                       else
                         @staff_availability.start_datetime
                       end
                     ),
                   endTime:
                     (
                       if @staff_availability.recurring?
                         @staff_availability.end_time.strftime("%H:%M")
                       else
                         @staff_availability.end_datetime
                       end
                     ),
                   recurring: @staff_availability.recurring,
                   timePeriodStart: time_period.start_date,
                   timePeriodEnd: time_period.end_date,
                   color:
                     hex_color_to_rgba(
                       @staff_availability
                         .user
                         .staff_spaces
                         .find_by(space: @user.space)
                         .color,
                       1
                     ),
                   id: @staff_availability.id,
                   userId: @staff_availability.user.id
                 }
        end
      else
        format.html { render :new }
        format.json do
          render json: {
                   errors: @staff_availability.errors
                 },
                 status: :unprocessable_entity
        end
      end
    end
  end

  def update
    # from staff availability form
    if params[:start_date].present? && params[:end_date].present?
      params_start_time = Time.parse(params[:staff_availability][:start_time])
      params_end_time = Time.parse(params[:staff_availability][:end_time])
      params_start_date = Date.parse(params[:start_date])
      params_end_date = Date.parse(params[:end_date])

      respond_to do |format|
        updated = if params.has_key?(:recurring)
          @staff_availability.update(
              staff_availability_params.except(
                :start_date,
                :end_date,
                :recurring
              ).merge(start_datetime: nil, end_datetime: nil, recurring: true)
            )
        else
          @staff_availability.update(
              staff_availability_params.except(
                :start_date,
                :end_date,
                :start_time,
                :end_time,
                :day,
                :recurring
              ).merge(
                start_datetime:
                  params_start_date +
                    params_start_time.seconds_since_midnight.seconds,
                end_datetime:
                  params_end_date +
                    params_end_time.seconds_since_midnight.seconds,
                start_time: nil,
                end_time: nil,
                day: nil,
                recurring: false
              )
            )
                  end

        if updated
          format.html do
            redirect_to staff_availabilities_path,
                        notice:
                          "The staff unavailability was successfully updated."
          end
          format.json { render json: { status: "ok" }, status: :ok }
        else
          format.html { render :edit }
          format.json do
            render json: @staff_availability.errors,
                   status: :unprocessable_entity
          end
        end
      end
      # from calendar
    elsif params[:staff_availability].present?
      respond_to do |format|
        params_start_date = Date.parse(params[:staff_availability][:start_date])
        params_end_date = Date.parse(params[:staff_availability][:end_date])

        params_start_time = Time.parse(params[:staff_availability][:start_time])
        params_end_time = Time.parse(params[:staff_availability][:end_time])
        params_start_time = Time.parse(params_start_time.strftime("%H:%M"))
        params_end_time = Time.parse(params_end_time.strftime("%H:%M"))

        update_params = {
          day: params[:staff_availability][:day],
          start_time: params_start_time.strftime("%H:%M"),
          end_time: params_end_time.strftime("%H:%M"),
          start_datetime:
            params_start_date +
              params_start_time.seconds_since_midnight.seconds,
          end_datetime:
            params_end_date + params_end_time.seconds_since_midnight.seconds
        }

        if params[:staff_availability][:exceptions_attributes].present?
          @staff_availability.update staff_availability_params.slice(
                                       :exceptions_attributes
                                     )
        end

        if @staff_availability.update(update_params)
          format.html do
            redirect_to staff_availabilities_path,
                        notice:
                          "The staff unavailability was successfully updated."
          end
          format.json { render json: { status: "ok" }, status: :ok }
        else
          format.html { render :edit }
          format.json do
            render json: @staff_availability.errors,
                   status: :unprocessable_entity
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
    @staff_availability.destroy
    respond_to do |format|
      format.html do
        redirect_to staff_availabilities_path,
                    notice: "The staff unavailability was successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  private

  def check_admin_or_staff_in_space
    return if @user && (@user.admin? || @user.staff_in_space?)
      redirect_to root_path
      flash[
        :alert
      ] = "You cannot access this area. If you think you should be able, try asking your manager if you were added in one of the spaces."
    
  end

  def set_staff_availabilities
    @staff_availability = StaffAvailability.find(params[:id])
  end

  def staff_availability_params
    params.require(:staff_availability).permit(
      :day, # recur on which day?
      :start_time,
      :start_date, # excepted
      :end_time,
      :end_date, # excepted
      :user_id,
      :time_period_id,
      :recurring,
      exceptions_attributes: [%i[covers start_at]]
    )
  end

  def set_selected_user
    @selected_user = if @user.admin?
      if params[:staff_id].present? && params[:staff_id] != "null" &&
           User.find(params[:staff_id]).present?
        User.find(params[:staff_id])
      else
        @user
                       end
    else
      @user
                     end
  end

  def set_time_period
    @missing_time_period = false
    if params[:time_period_id] &&
         TimePeriod.find(params[:time_period_id]).present?
      @time_period = TimePeriod.find(params[:time_period_id])
    elsif TimePeriod.current.present?
      @time_period = TimePeriod.current
      else
        @missing_time_period = true
    end
  end

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end
end
