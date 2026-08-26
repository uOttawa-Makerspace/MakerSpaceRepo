class LockerRentalsController < SessionsController
  before_action :current_user
  before_action :signed_in
  # Also sets @locker_rental
  before_action :check_permission, except: %i[index new create]
  layout 'staff_area', only: [:admin]
  layout 'admin_area', only: [:assign_locker]

  def index
    @own_locker_rentals = current_user.locker_rentals
  end

  def expired
    @expired_locker_rentals =
      LockerRental.active.where(owned_until: ..DateTime.current)
  end

  def admin
    base_rentals = LockerRental.includes(:locker, :rented_by).order(created_at: :desc).not_cancelled
    
    # Requirement: Split between requests that have been dealt with vs requests that have not been looked at
    @pending_requests = base_rentals.reviewing
    @active_rentals = base_rentals.where(state: %i[await_payment active])

    respond_to do |format|
      format.json { render json: { pending: @pending_requests, active: @active_rentals } }
      format.all { render layout: 'staff_area' }
    end
  end

  def assign_locker
    @locker_rental = LockerRental.new
  end

  def show
    # Staff can assign any locker, so they get nil (no audience filter). 
    # Regular users are filtered so they only see their allowed lockers.
    audience = if current_user.staff? then nil
               elsif current_user.student? then 'gng'
               else 'general'
               end

    # Only show available lockers matching the user's audience
    @locker_select_options =
      Locker.available(audience).order_by_specifier.map do |locker|
        [
          locker.specifier,
          locker.id,
          { data: { size: locker.locker_size.size, staff_only: !locker.available } }
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
    # Allow staff to assign lockers
    unless current_user.staff? || LockerOption.lockers_enabled
      flash[:alert] = 'New locker rentals are not currently accepted.'
      redirect_to locker_rentals_path
      return
    end

    # Force all new lockers to be assigned to the user submitting the request
    @locker_rental =
      LockerRental.new(
        locker_rental_params.with_defaults(rented_by_id: current_user.id)
      )

    # If locker rental needs a decision
    unless @locker_rental.reviewing?
      @locker_rental.decided_by = current_user
      # Explicitly handle indefinite state so it overrides any submitted dates
      if @locker_rental.indefinite == '1'
        @locker_rental.owned_until = nil
      else
        @locker_rental.owned_until ||= end_of_this_semester
      end
    end

    if @locker_rental.save
      redirect_back fallback_location: :new_locker_rental,
                    notice: ('Locker assigned' if @locker_rental.active?)
    else
      new_instance_attributes
      render :new, status: :unprocessable_content
    end
  end

  def update
    @locker_rental = LockerRental.find(params[:id])
    unless current_user.staff? || current_user == @locker_rental.rented_by
      respond_to do |format|
        format.html { redirect_to locker_rentals_path }
        format.json { head :forbidden }
      end
      return
    end

    # Assign new parameters but don't commit yet
    @locker_rental.assign_attributes(locker_rental_params)

    @locker_rental.decided_by = current_user

    # Requirement: Ideally I would like to have an 'indefinite' option for the date
    # We check this if the state is changing to active OR if it's already active (Move Locker)
    if @locker_rental.indefinite == '1'
      @locker_rental.owned_until = nil
    elsif (@locker_rental.state_changed?(to: :active) || @locker_rental.active?) && @locker_rental.owned_until.blank?
      @locker_rental.owned_until = end_of_this_semester
    end

    # Only staff can cancel a paid locker
    if @locker_rental.state_changed?(from: :active, to: :cancelled) &&
         !current_user.staff?
      flash[:alert] = 'Please contact administration for cancelling a locker'
      respond_to do |format|
        format.html { render :show, status: :unprocessable_content }
        format.json { render json: { error: 'Unauthorized' }, status: :unprocessable_entity }
      end
      return
    end

    if @locker_rental.save
      respond_to do |format|
        format.html do
          flash[:notice] = 'Locker rental updated'
          redirect_back fallback_location: :locker_rentals
        end
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          flash[:alert] = 'Failed to update locker rental' + helpers.tag.br +
            @locker_rental.errors.full_messages.join(helpers.tag.br)
          redirect_back fallback_location: :locker_rentals
        end
        format.json { render json: @locker_rental.errors, status: :unprocessable_entity }
      end
    end
  end

  def renew
    @locker_rental = LockerRental.find(params[:id])
    unless current_user.staff? || current_user == @locker_rental.rented_by
      redirect_to locker_rentals_path
      return
    end

    unless @locker_rental.renewable?
      redirect_to @locker_rental, alert: 'This locker rental is not renewable.'
      return
    end

    @locker_rental.assign_attributes(
      state: :await_payment,
      decided_by: current_user,
      owned_until: end_of_this_semester
    )

    if @locker_rental.save
      redirect_to @locker_rental,
                  notice: 'Locker renewal started. Please complete checkout to renew your locker.'
    else
      flash[:alert] = 'Could not start renewal: ' +
        @locker_rental.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  # Requirement: Have a column like 'contacted' with a checkbox so I can keep track if I email people
  def toggle_contacted
    # Security check: only staff can modify clearance contacted status
    unless current_user.staff?
      head :forbidden
      return
    end

    @locker_rental.update_column(:contacted_for_clearance, !@locker_rental.contacted_for_clearance)
    head :no_content
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
    @locker_product_info = LockerOption.locker_product_info || { variants: {} }
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
      contacted_for_clearance
      indefinite # Permit the indefinite virtual attribute
    ]

    staff_additional_permitted = %i[
      locker_id
      rented_by_id
      repository_id
      requested_as
      state
      owned_until
      notes
      staff_notes
      contacted_for_clearance
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
