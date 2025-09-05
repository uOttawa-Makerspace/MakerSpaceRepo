class LockerRentalsController < SessionsController
  before_action :current_user
  before_action :signed_in
  # Also sets @locker_rental
  before_action :check_permission, except: %i[index new create]

  def index
    @own_locker_rentals = current_user.locker_rentals
  end

  def admin
    @current_rental_state = params[:rental_state] || "reviewing"

    @locker_rentals =
      LockerRental.includes(:locker_type, :rented_by).order(
        locker_type_id: :asc
      )

    respond_to do |format|
      format.json { render json: @locker_rentals }
      format.all { render layout: "staff_area" }
    end
  end

  def show
  end

  def edit
    @locker_rental = LockerRental.find(params[:id])
    new_instance_attributes
  end

  def new
    @locker_rental = LockerRental.new
    # Only locker types enabled by admin
    new_instance_attributes
  end

  def create
    @locker_rental = LockerRental.new(locker_rental_params)

    # If locker rental needs a decision
    @locker_rental.decided_by = current_user unless @locker_rental.reviewing?

    if @locker_rental.save
      redirect_back fallback_location: :new_locker_rental
    else
      new_instance_attributes
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @locker_rental = LockerRental.find(params[:id])
    unless current_user.staff? || current_user == @locker_rental.rented_by
      redirect_to locker_rentals_path
    end

    # Assign new parameters but don't commit yet
    @locker_rental.assign_attributes(locker_rental_params)

    if @locker_rental.state_changed?(from: :reviewing)
      @locker_rental.decided_by = current_user
    end

    # FIXME: move this to model
    if @locker_rental.state_changed?(to: :active)
      # default to end of semester
      @locker_rental.owned_until ||= end_of_this_semester
    end

    # Only staff can cancel a paid locker
    if @locker_rental.state_changed?(from: :active, to: :cancelled) &&
         !current_user.staff?
      flash[:alert] = "Please contact administration for cancelling a locker"
      render :show, status: :unprocessable_entity
      return
    end

    if @locker_rental.save
      flash[:notice] = "Locker rental updated"
    else
      flash[:alert] = "Failed to update locker rental" + helpers.tag.br +
        @locker_rental.errors.full_messages.join(helpers.tag.br)
    end

    redirect_back fallback_location: :locker_rentals
  end

  private

  def check_permission
    # If user accesses a locker rental by ID
    if params[:id].present?
      @locker_rental = LockerRental.find(params[:id])
      # Allow if getting own locker rental
      return if @locker_rental.rented_by == current_user
    end
    # Always allow staff
    return if current_user.staff?

    redirect_to locker_rentals_path
  end

  def new_instance_attributes
    @user_repositories = current_user.repositories.pluck(:title, :id)
    # FIXME localize this later
    @available_fors = {
      staff: ("CEED staff member" if current_user.staff?),
      student: ("GNG student" if current_user.student?),
      general: "community member"
    }.compact.invert
    # Don't allow new request if user already has an active or pending request
    @pending_locker_request = current_user.locker_rentals.pending.first
  end

  # Admins are allowed to cancel and assign
  def admin_locker_rental_params
    admin_params =
      params.require(:locker_rental).permit(
        :locker_id,
        :rented_by_id,
        :repository,
        :requested_as,
        :state,
        :owned_until,
        :notes
      )
    # FIXME replace that search with a different one, return ID instead
    # If username is given (since search can do that)
    rented_by_user =
      User.find_by(username: params.dig(:locker_rental, :rented_by_username))
    if rented_by_user
      # then convert to user id
      admin_params.reverse_merge!(rented_by_id: rented_by_user.id)
    end
    return admin_params
  end

  def locker_rental_params
    if current_user.staff?
      admin_locker_rental_params
    elsif params[:id] # If updating, only allow cancellations
      params.require(:locker_rental).permit(:state)
    else # If new, only allow some details
      params.require(:locker_rental).permit(
        :notes,
        :requested_as,
        :repository_id
      )
    end.with_defaults(rented_by_id: current_user.id, owned_until: end_of_this_semester)
  end
end
