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
    base_rentals = LockerRental.includes(:locker, :rented_by, :locker_payments).order(created_at: :desc).not_cancelled
    
    # Requirement: Split between requests that have been dealt with vs requests that have not been looked at
    @pending_requests = base_rentals.reviewing
    @active_rentals = base_rentals.where(state: %i[await_payment active])
    # Paid, but the payment could not be applied: staff must decide. Includes cancelled rentals (their payment
    # is still unresolved). The same scope drives the badge in the tables below.
    @held_rentals = LockerRental.with_held_payment.includes(:locker, :rented_by, :locker_payments).order(created_at: :desc)

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

    # Staff named a renter who does not exist: refuse, never fall back to themself
    # (the fallback below is only for a request that names no renter at all).
    if unknown_renter_username?
      @locker_rental = LockerRental.new
      @locker_rental.errors.add(:base, RENTER_NOT_FOUND)
      new_instance_attributes
      render :new, status: :unprocessable_content
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
      @locker_rental.notify_after_commit
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

    if unknown_renter_username?
      respond_to do |format|
        format.html do
          flash[:alert] = "Failed to update locker rental#{helpers.tag.br}#{RENTER_NOT_FOUND}".html_safe
          redirect_back fallback_location: :locker_rentals
        end
        format.json { render json: { base: [RENTER_NOT_FOUND] }, status: :unprocessable_entity }
      end
      return
    end

    # Everything below runs on the row locked FOR UPDATE and reloaded: the guards, the save, the settlement of
    # held payments and the mail all see the CURRENT state (a webhook payment may have activated or the other
    # staff member cancelled it since this page was rendered), and a concurrent webhook waits for the commit.
    outcome = nil
    LockerRental.transaction do
      @locker_rental.lock!

      if stale_page?
        outcome = :stale
      else
        # Assign new parameters but don't commit yet
        @locker_rental.assign_attributes(locker_rental_params)
        @locker_rental.decided_by = current_user

        # Requirement: Ideally I would like to have an 'indefinite' option for the date
        # We check this if the state is changing to active OR if it's already active (Move Locker)
        if @locker_rental.indefinite == '1'
          @locker_rental.owned_until = nil
        elsif (@locker_rental.state_changed?(to: :active) || (current_user.staff? && @locker_rental.active?)) &&
              @locker_rental.owned_until.blank?
          @locker_rental.owned_until = end_of_this_semester
        end

        if renter_state_change_refused?
          outcome = :state_refused
        elsif @locker_rental.save
          # Assigning the rental active also settles one held payment, in the same transaction as the save.
          if current_user.staff? && @locker_rental.saved_change_to_state? && @locker_rental.active?
            @locker_rental.settle_held_payments!(by: current_user)
          end
          outcome = :saved
        else
          outcome = :invalid
        end
      end
    end

    case outcome
    when :stale
      stale_page_response
    when :state_refused
      flash[:alert] = if @locker_rental.state_was == 'active' && @locker_rental.cancelled?
                        'Please contact administration for cancelling a locker'
                      else
                        'You can only cancel a pending request'
                      end
      respond_to do |format|
        format.html { render :show, status: :unprocessable_content }
        format.json { render json: { error: 'Unauthorized' }, status: :unprocessable_entity }
      end
    when :saved
      @locker_rental.notify_after_commit
      # Committed; only now the Shopify call (no transaction, no row lock held)
      draft_synced = @locker_rental.sync_shopify_draft_order_after_commit
      warning = draft_synced ? nil : draft_not_removed_message
      respond_to do |format|
        format.html do
          if warning
            flash[:alert] = warning
          else
            flash[:notice] = 'Locker rental updated'
          end
          redirect_back fallback_location: :locker_rentals
        end
        # 204 normally; 200 with { warning: ... } when the rental was updated but its Shopify checkout could not
        # be removed, so a JSON client can tell the difference.
        format.json { warning ? render(json: { warning: warning }, status: :ok) : head(:no_content) }
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

    # Locked and reloaded first, so renewable? and the save see the current row.
    outcome = nil
    LockerRental.transaction do
      @locker_rental.lock!
      if @locker_rental.renewable?
        @locker_rental.assign_attributes(
          state: :await_payment,
          decided_by: current_user,
          owned_until: end_of_this_semester
        )
        outcome = @locker_rental.save ? :saved : :invalid
      else
        outcome = :not_renewable
      end
    end

    case outcome
    when :not_renewable
      redirect_to @locker_rental, alert: 'This locker rental is not renewable.'
    when :saved
      @locker_rental.notify_after_commit
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

  RENTER_NOT_FOUND = 'User not found'

  # The cancellation is committed but Shopify did not confirm the draft order delete (reported to staff).
  def draft_not_removed_message
    if current_user.staff?
      'Locker rental cancelled, but its Shopify checkout could not be removed. ' \
        'A payment made on it will appear under "Paid, needs a decision". The error was reported.'
    else
      "Your request was cancelled. If you still see a payment link, don't use it; staff have been notified."
    end
  end

  # The one rule for non-staff: the only state changes a renter may make on their own rental. Everything
  # else (activating, sending to payment, reviewing, ending a paid rental) is staff's.
  RENTER_STATE_CHANGES = [%w[reviewing cancelled], %w[await_payment cancelled]].freeze

  def renter_state_change_refused?
    !current_user.staff? && @locker_rental.state_changed? &&
      RENTER_STATE_CHANGES.exclude?([@locker_rental.state_was, @locker_rental.state])
  end

  # The staff forms send the state the page was rendered with. If the locked row has moved on (a payment
  # activated it, someone else cancelled it) the action is refused instead of applied on a stale view, so e.g.
  # a cancel of "unpaid" can never land on a rental that has just been paid.
  def stale_page?
    params[:expected_state].present? && params[:expected_state] != @locker_rental.state
  end

  def stale_page_response
    message = "This locker rental changed while you had the page open (it is now #{@locker_rental.state}). " \
              'Reload it and review before acting.'
    respond_to do |format|
      format.html do
        flash[:alert] = message
        redirect_to @locker_rental
      end
      format.json { render json: { error: message }, status: :conflict }
    end
  end

  # A staff request that names a renter by username that matches no user, and names no renter by id. When an
  # id is sent it wins and the username is only the display text of the search box. A deleted or deactivated
  # user found by id (or by username) fails the rental's eligibility validation instead.
  def unknown_renter_username?
    username = params.dig(:locker_rental, :rented_by_username)
    current_user.staff? && username.present? && params.dig(:locker_rental, :rented_by_id).blank? &&
      !User.unscoped.exists?(username: username.to_s)
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
        User.unscoped.find_by(username: params.dig(:locker_rental, :rented_by_username))
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
