class LockerRentalsController < SessionsController
  before_action :current_user
  before_action :signed_in, except: %i[stripe_success stripe_cancelled]
  # Also sets @locker_rental
  before_action :check_permission,
                except: %i[index new create stripe_success stripe_cancelled]

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
      format.all {render layout: 'admin_area'}
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
    # if not admin member or has debug value set
    # then force to wait for admin approval
    if !current_user.staff? || params.dig(:locker_rental, :ask)
      @locker_rental.state = :reviewing
      # If not admin, only create request for self
      @locker_rental.rented_by = current_user
    elsif current_user.staff? && locker_rental_params[:state] == "active"
      # if acting as admin
      # save down later
      @locker_rental.auto_assign
    end

    # validate locker type if not administration
    unless current_user.staff?
      # not an admin, asking for an unavailable locker
      unless @locker_rental.locker_type.available
        new_instance_attributes
        render :new, status: :unprocessable_entity
        return
      end

      if @locker_rental.locker_type.get_available_lockers.empty?
        new_instance_attributes
        render :new, status: :unprocessable_entity
        return
      end
    end

    if @locker_rental.save
      redirect_back fallback_location: :new_locker_rental
    else
      new_instance_attributes
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @locker_rental = LockerRental.find(params[:id])

    # NOTE move this line to model maybe?
    # if changing state to 'active'
    if current_user.staff? && locker_rental_params[:state] == "active"
      # default to end of semester
      @locker_rental.owned_until ||= end_of_this_semester
      # Get first available locker specifier if not set
      @locker_rental.locker_specifier ||=
        @locker_rental.locker_type.get_available_lockers.first
    end

    # Only admins can cancel active rentals
    # If current user is attempting to change state
    if !current_user.staff? && locker_rental_params[:state].present?
      # prevent if not cancelling a non-active rental
      unless locker_rental_params[:state] == "cancelled" &&
               @locker_rental.pending?
        flash[
          :alert
        ] = "Cannot cancel active locker rental, contact administration for cancellation"
        render :show, status: :unprocessable_entity
        return
      end
    end

    if @locker_rental.update(locker_rental_params)
      flash[:notice] = "Locker rental updated"
    else
      flash[:alert] = "Failed to update locker rental" + helpers.tag.br +
        @locker_rental.errors.full_messages.join(helpers.tag.br)
    end

    redirect_back fallback_location: :locker_rentals
  end

  def stripe_success
  end

  def stripe_cancelled
  end

  private

  def check_permission
    # If user gives a request id
    if params[:id].present?
      @locker_rental = LockerRental.find(params[:id])
      # Allow if getting own locker rental
      return if @locker_rental.rented_by == current_user
    end
    # Always allow staff
    return if current_user.staff?

    redirect_to :index
  end

  # FIXME: these three functions below are too big and complicated
  def new_instance_attributes
    # @available_locker_types = LockerType.available.map do |t|
    #   ["#{t.short_form}#{' - none available' if t.quantity_available.zero?}",
    #    t.id, {disabled: t.quantity_available.zero?}]
    # end
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

  def admin_locker_rental_params
    admin_params =
      params.require(:locker_rental).permit(
        :locker_type_id,
        # admin can assign and approve requests
        :rented_by_id,
        :locker_specifier,
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
    if current_user.staff? && !params.dig(:locker_rental, :ask)
      admin_locker_rental_params
    else
      # people pick where they want a locker
      permits = [:locker_type_id]
      unless params[:id]
        # prevent user from editing rental notes after first submit
        permits << :notes
        permits << :requested_as
        permits << :repository_id
      end
      # For user cancellations
      permits << :state
      params.require(:locker_rental).permit(*permits)
    end
  end
end
