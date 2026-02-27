class LockerRentalsController < SessionsController
  before_action :current_user
  before_action :signed_in
  # Also sets @locker_rental
  before_action :check_permission, except: %i[index new create]
  layout 'staff_area', only: [:admin] # as in admin tools but staff can access it
  layout 'admin_area', only: [:assign_locker]

  def index
    @own_locker_rentals = current_user.locker_rentals
  end

  def expired
    @expired_locker_rentals =
      LockerRental.active.where(owned_until: ..DateTime.current)
  end

  def admin
    @current_rental_state = params[:rental_state] || 'reviewing'

    @locker_rentals =
      LockerRental
        .includes(:locker, :rented_by)
        .order(created_at: :desc)
        .not_cancelled

    respond_to do |format|
      format.json { render json: @locker_rentals }
      format.all { render layout: 'staff_area' }
    end
  end

  def assign_locker
    @locker_rental = LockerRental.new
  end

  def show
    @locker_select_options =
      Locker.available.order_by_specifier.map do |locker|
        [
          locker.specifier,
          locker.id,
          { data: { size: locker.locker_size.size } }
        ]
      end

    if @locker_rental&.locker
      @locker_select_options.prepend [
        @locker_rental.locker.specifier,
        @locker_rental.locker.id,
        { data: { size: @locker_rental.locker.locker_size.size } }
      ]
    end
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
    unless LockerOption.lockers_enabled
      flash[:alert] = 'New locker rentals are not currently accepted.'
      redirect_to locker_rentals_path
      return
    end

    @locker_rental =
      LockerRental.new(
        locker_rental_params.with_defaults(rented_by_id: current_user.id)
      )

    # If locker rental needs a decision
    unless @locker_rental.reviewing?
      @locker_rental.decided_by = current_user
      @locker_rental.owned_until ||= end_of_this_semester
    end

    if @locker_rental.save
      redirect_back fallback_location: :new_locker_rental
    else
      new_instance_attributes
      render :new, status: :unprocessable_content
    end
  end

  def update
    @locker_rental = LockerRental.find(params[:id])
    unless current_user.staff? || current_user == @locker_rental.rented_by
      redirect_to locker_rentals_path
    end

    # Assign new parameters but don't commit yet
    @locker_rental.assign_attributes(locker_rental_params)

    @locker_rental.decided_by = current_user

    # FIXME: move this to model
    if @locker_rental.state_changed?(to: :active)
      # default to end of semester
      @locker_rental.owned_until ||= end_of_this_semester
    end

    # Only staff can cancel a paid locker
    if @locker_rental.state_changed?(from: :active, to: :cancelled) &&
         !current_user.staff?
      flash[:alert] = 'Please contact administration for cancelling a locker'
      render :show, status: :unprocessable_content
      return
    end

    if @locker_rental.save
      flash[:notice] = 'Locker rental updated'
    else
      flash[:alert] = 'Failed to update locker rental' + helpers.tag.br +
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
    # FIXME localize this later
    @available_fors = {
      staff: ('CEED staff member' if current_user.staff?),
      student: ('GNG student' if current_user.student?),
      general: 'General request'
    }.compact.invert
    # Don't allow new request if user already has an active or pending request
    @pending_locker_request = current_user.locker_rentals.pending.first
    @locker_product_info = LockerOption.locker_product_info
  end

  def locker_rental_params
    common_permitted = %i[
      preferred_locker_id
      notes
      requested_as
      repository_id
      course_name_id
      section_name
      team_name
    ]

    staff_additional_permitted = %i[
      locker_id
      rented_by_id
      repository_id
      requested_as
      state
      owned_until
      notes
    ]

    if current_user.staff?
      admin_params =
        params.require(:locker_rental).permit(
          *common_permitted,
          *staff_additional_permitted
        )

      # FIXME replace that search with a different one, return ID instead
      # If username is given (since search can do that)
      rented_by_user =
        User.find_by(username: params.dig(:locker_rental, :rented_by_username))
      if rented_by_user
        # then convert to user id
        admin_params.reverse_merge!(rented_by_id: rented_by_user.id)
      end

      admin_params
    elsif params[:id]
      # If updating, only allow cancellations
      params.require(:locker_rental).permit(:state)
    else
      params.require(:locker_rental).permit(*common_permitted)
    end
  end
end
