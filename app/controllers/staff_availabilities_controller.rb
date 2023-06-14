class StaffAvailabilitiesController < ApplicationController
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
    puts(@time_period.id)
    @selected_user
      .staff_availabilities
      .where(time_period: @time_period)
      .each do |a|
        event = {}
        event["title"] = "Unavailable"
        event["id"] = a.id
        event["daysOfWeek"] = [a.day]
        event["startTime"] = a.start_time.strftime("%H:%M")
        event["endTime"] = a.end_time.strftime("%H:%M")
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
    @staffs = User.all.where(id: StaffSpace.all.map(&:user_id).uniq)
    @time_periods = TimePeriod.all
  end

  def create
    if params[:staff_availability][:time_period_id].present? ||
         @time_period.present?
      time_period_id =
        (
          if params[:staff_availability][:time_period_id].present?
            params[:staff_availability][:time_period_id]
          else
            @time_period.id
          end
        )
    elsif params[:time_period_id].present? || @time_period.present?
      time_period_id =
        (
          if params[:time_period_id].present?
            params[:time_period_id]
          else
            @time_period.id
          end
        )
    end

    if params[:start_date].present? && params[:end_date].present? &&
         time_period_id.present?
      start_date = DateTime.parse(params[:start_date])
      end_date = DateTime.parse(params[:end_date])
      @staff_availability =
        StaffAvailability.new(
          user_id: @selected_user.id,
          day: start_date.wday,
          start_time: start_date.strftime("%H:%M"),
          end_time: end_date.strftime("%H:%M"),
          time_period_id: time_period_id
        )
    elsif params[:staff_availability].present? && time_period_id.present?
      @staff_availability =
        StaffAvailability.new(
          staff_availability_params.merge(
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

    respond_to do |format|
      if @staff_availability.save!
        format.html do
          redirect_to staff_availabilities_path,
                      notice:
                        "The staff unavailabilities were successfully created."
        end
        format.json do
          render json: {
                   title: "#{@staff_availability.user.name} is unavailable",
                   daysOfWeek: [@staff_availability.day],
                   startTime: @staff_availability.start_time.strftime("%H:%M"),
                   endTime: @staff_availability.end_time.strftime("%H:%M"),
                   color:
                     hex_color_to_rgba(
                       @staff_availability
                         .user
                         .staff_spaces
                         .find_by(space: @user.space)
                         .color,
                       1
                     ),
                   id: @staff_availability.id
                 }
        end
      else
        format.html { render :new }
        format.json do
          render json: @staff_availability.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    if params[:staff_availability].present?
      respond_to do |format|
        if @staff_availability.update(staff_availability_params)
          format.html do
            redirect_to staff_availabilities_path,
                        notice:
                          "The staff unavailability was successfully updated."
          end
          format.json { render :index, status: :ok }
        else
          format.html { render :edit }
          format.json do
            render json: @staff_availability.errors,
                   status: :unprocessable_entity
          end
        end
      end
    elsif params[:start_date].present? && params[:end_date]
      start_date = DateTime.parse(params[:start_date])
      end_date = DateTime.parse(params[:end_date])
      respond_to do |format|
        if @staff_availability.update(
             start_time: start_date.strftime("%H:%M"),
             end_time: end_date.strftime("%H:%M"),
             day: start_date.wday
           )
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
    unless @user && (@user.admin? || @user.staff_in_space?)
      redirect_to root_path
      flash[
        :alert
      ] = "You cannot access this area. If you think you should be able, try asking your manager if you were added in one of the spaces."
    end
  end

  def set_staff_availabilities
    @staff_availability = StaffAvailability.find(params[:id])
  end

  def staff_availability_params
    params.require(:staff_availability).permit(
      :day,
      :start_time,
      :end_time,
      :user_id,
      :time_period_id
    )
  end

  def set_selected_user
    if @user.admin?
      if params[:staff_id].present? && params[:staff_id] != "null" &&
           User.find(params[:staff_id]).present?
        @selected_user = User.find(params[:staff_id])
      else
        @selected_user = @user
      end
    else
      @selected_user = @user
    end
  end

  def set_time_period
    @missing_time_period = false
    if params[:time_period_id] &&
         TimePeriod.find(params[:time_period_id]).present?
      @time_period = TimePeriod.find(params[:time_period_id])
    else
      if TimePeriod.current.present?
        @time_period = TimePeriod.current
      else
        @missing_time_period = true
      end
    end
  end

  def hex_color_to_rgba(hex, opacity)
    rgb = hex.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgba(#{rgb.join(", ")}, #{opacity})"
  end
end
