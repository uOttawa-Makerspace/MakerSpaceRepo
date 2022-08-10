class StaffAvailabilitiesController < StaffAreaController
  before_action :check_admin_or_staff_in_space
  before_action :set_staff_availabilities, only: %i[edit update destroy]
  before_action :set_selected_user

  def index
    @user_availabilities =
      @selected_user.staff_availabilities.order(:day, :start_time)
    @staff_availabilities =
      StaffAvailability.all.order(:user_id, :day, :start_time) if @user.admin?
  end

  def get_availabilities
    staff_availabilities = []
    @selected_user.staff_availabilities.each do |a|
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
  end

  def edit
    @staffs = User.all.where(id: StaffSpace.all.map(&:user_id).uniq)
  end

  def create
    if params[:staff_availability].present?
      @staff_availability =
        StaffAvailability.new(
          staff_availability_params.merge(user_id: @selected_user.id)
        )
    elsif params[:start_date].present? && params[:end_date].present?
      start_date = DateTime.parse(params[:start_date])
      end_date = DateTime.parse(params[:end_date])
      @staff_availability =
        StaffAvailability.new(
          user_id: @selected_user.id,
          day: start_date.wday,
          start_time: start_date.strftime("%H:%M"),
          end_time: end_date.strftime("%H:%M")
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
        format.json { render json: { id: @staff_availability.id } }
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
    unless @user.admin? || @user.staff_in_space?
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
      :user_id
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
end
