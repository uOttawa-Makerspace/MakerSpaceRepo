class SubSpaceBookingController < SessionsController
  before_action :no_container
  before_action :user_account
  before_action :user_approved, only: [:create]
  before_action :user_admin_or_staff,
                only: %i[
                  approve
                  decline
                  approve_access
                  bulk_approve_access
                  deny_access
                  users
                  get_sub_space_booking
                  bulk_approve_decline
                ]
  before_action :user_admin, only: [:publish]
  before_action :user_booking_belongs, only: %i[delete edit update]

  # We're using the standard layout, no real control over the partial rendering
  before_action -> { @with_sub_space = true }

  def index
    if params[:room].present?
      @subspace = SubSpace.find(params[:room])
      @rules = []
      if @subspace.maximum_booking_duration.present?
        @rules << "has a maximum booking duration of #{@subspace.maximum_booking_duration} hours"
      end
      if @subspace.maximum_booking_hours_per_week.present?
        @rules << "has a maximum booking hours per person per week of #{@subspace.maximum_booking_hours_per_week} hours"
      end
      @rules << "bookings (Name and Description of event) are public by default" if @subspace.default_public
      if @subspace.max_automatic_approval_hour.present? &&
          @subspace.approval_required
        @rules << "Bookings require manual approval, bookings of #{@subspace.max_automatic_approval_hour} hours or less will be automatically approved"
      elsif @subspace.approval_required
        @rules << "bookings will require manual approval"
      end
    end
    @bookings =
      SubSpaceBooking
        .where(user_id: current_user.id)
        .joins(:user)
        .includes(:sub_space)
        .order(start_time: :desc)

    if current_user.admin?
      @current_time = Time.now
      
      @pagy_pending, @pending_bookings = current_bookings(BookingStatus.pending.id, page_key: "pending_page")
      load_recurring_bookings_for_page(@pending_bookings)
      
      @pagy_approved, @approved_bookings = current_bookings(BookingStatus.approved.id, page_key: "approved_page")
      @pagy_declined, @declined_bookings = current_bookings(BookingStatus.declined.id, page_key: "declined_page")
      @pagy_old_pending, @old_pending_bookings = old_bookings(BookingStatus.pending.id, page_key: "old_pending_page")
      @pagy_old_approved, @old_approved_bookings = old_bookings(BookingStatus.approved.id, page_key: "old_approved_page")
      @pagy_old_declined, @old_declined_bookings = old_bookings(BookingStatus.declined.id, page_key: "old_declined_page")
    end

    @supervisors = []
    SpaceManagerJoin.includes(:user).each do |smj|
      @supervisors << [smj.user.name, smj.user.id] unless @supervisors.include?([smj.user.name, smj.user.id])
    end
    @supervisors = @supervisors.sort_by { |elem| elem[0].downcase }
  end

  def request_access
    if params[:comments].blank?
      flash[:alert] = "Please provide a reason for booking access."
      redirect_to root_path
      return
    end

    emails = access_request_recipients(params[:identity])
    if emails.nil?
      redirect_to root_path
      return
    end

    if UserBookingApproval.where(user: current_user).first.nil?
      booking_approval =
        UserBookingApproval.new(
          user: current_user,
          date: Time.now,
          comments: params[:comments],
          approved: false,
          identity: params[:identity]
        )

      if booking_approval.save
        BookingMailer.send_booking_approval_request_sent(
          booking_approval.id,
          emails
        ).deliver_later

        flash[:notice] = "Access request submitted successfully."
      else
        flash[:alert] = booking_approval.errors.full_messages.join(", ")
      end
    else
      flash[:alert] = "You have already requested access."
    end
    redirect_to root_path
  end

  def approve_access
    if params[:id].nil?
      user = User.find(params[:user_id])
      uba = UserBookingApproval.find_or_initialize_by(user: user)
      if uba.approved? && user.booking_approval?
        redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                    notice: "#{user.name} already has booking access."
        return
      end
      id = grant_booking_access!(uba)
      BookingMailer.send_booking_approval_request_approved(id).deliver_later
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  notice: "Access granted successfully."
    else
      uba = UserBookingApproval.find(params[:id])
      if uba.approved? && uba.user.booking_approval?
        redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                    notice: "#{uba.user.name} already has booking access."
        return
      end
      id = grant_booking_access!(uba)
      BookingMailer.send_booking_approval_request_approved(id).deliver_later
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  notice: "Access request approved successfully."
    end
  rescue ActiveRecord::RecordInvalid => e
    approval_failed(e)
  end

  def deny_access
    uba = UserBookingApproval.find(params[:id])
    UserBookingApproval.transaction do
      uba.user.update_column(:booking_approval, false)
      uba.destroy!
    end
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: "Access request declined successfully."
  end

  def bulk_approve_access
    if params[:user_booking_approval_ids].blank?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: "No approvals selected."
      return
    end

    approved_ids = grant_pending_access(params[:user_booking_approval_ids])
    approved_ids.each do |id|
      BookingMailer.send_booking_approval_request_approved(id).deliver_later
    end

    skipped = Array(params[:user_booking_approval_ids]).uniq.size - approved_ids.size
    set_bulk_result_flash(
      approved_ids.size,
      skipped,
      notice: "Selected access requests approved successfully.",
      all_notice: "All selected access requests approved successfully.",
      alert: "#{skipped} selected request(s) were already approved and were skipped."
    )
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab")
  rescue ActiveRecord::RecordInvalid => e
    approval_failed(e)
  end

  # Typeahead for the "grant access" picker: at most 30 non-deleted users whose name or username contains the
  # query, as id and name. A blank or too short query lists nobody.
  def users
    render json: User.directory_search(params[:query]).order(:name, :id).as_json(only: %i[id name])
  end

  def bookings
    current_user
    @viewer_may_open_details = viewer_may_open_details
    @bookings = params[:room].present? ? feed_bookings.map { |booking| feed_event(booking) } : []
    # TODO: Allow search by recurring id
    render json: @bookings
  end

  def create
    attrs = sub_space_booking_params # a body without sub_space_booking is a 400
    recurring = params[:sub_space_booking][:recurring] == true
    # one clock read for the whole request. Every occurrence is judged
    # past or not once, against this instant, and its save validates against
    # the same instant, so the two can never disagree.
    now = Time.current

    # Permission first: a non-admin asking to block gets the forbidden answer,
    # whatever else is wrong with the request.
    if ActiveModel::Type::Boolean.new.cast(attrs[:blocking]) &&
         !current_user.admin?
      message = "You do not have permission to block a space."
      respond_to do |format|
        format.json do
          render json: { errors: [message] }, status: :forbidden
        end
        format.html do
          flash[:alert] = message
          redirect_to sub_space_booking_index_path
        end
      end
      return
    end

    booking = new_occurrence(attrs, now)
    booking.valid_without_status?
    # A recurring series skips its past occurrences instead of failing, so a
    # past first occurrence is not an error yet (see book_series).
    booking.errors.delete(:start_time, :in_the_past) if recurring
    if booking.errors.any?
      render_booking_failure(invalid_booking_failure(booking))
      return
    end

    if recurring
      end_date = series_end_date # nil when missing or malformed
      unless end_date && params[:sub_space_booking][:recurring_frequency].present?
        render json: {
                 errors: "Invalid recurring parameters"
               },
               status: :unprocessable_content
        return
      end
      if end_date > booking.start_time.to_date + SERIES_MAX_DAYS.days
        message = I18n.t("sub_space_booking.series.too_long", days: SERIES_MAX_DAYS)
        render_booking_failure(errors: ["Recurring #{message}"], alert: message)
        return
      end
      book_series(attrs, BookingSeries.new(booking.start_time, booking.end_time, end_date, params[:sub_space_booking][:recurring_frequency]), now)
    else
      failure = book_occurrence(booking)
      if failure
        render_booking_failure(failure)
      else
        render_booking_success(booking.sub_space)
      end
    end
  end

  def edit
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    if (
         @sub_space_booking.pending? && !@user.admin? &&
           !@user.eql?(@sub_space_booking.user)
       ) || (@sub_space_booking.approved? && !@user.admin?)
      redirect_to sub_space_booking_index_path,
                  alert: "You can't access this subspace booking."
    end
  end

  def update
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    if @sub_space_booking.approved? && !@user.admin?
      redirect_to sub_space_booking_index_path(
                    anchor: "booking-calendar-tab",
                    room: @sub_space_booking.sub_space_id
                  ),
                  alert: "You do not have permission to edit this booking"
      return
    end

    # Check the overlap and the limits against the values the model will store
    # (zoned, the user's own offsets included), not against a re-parsed copy of
    # the raw params. A blank start/end is not sent on (the stored
    # times stay); an unparseable one leaves the time nil, and the model's
    # presence check answers it.
    @sub_space_booking.assign_attributes(sub_space_booking_update_params)
    times_present = @sub_space_booking.start_time.present? && @sub_space_booking.end_time.present?

    # The overlap is checked in the room the booking ends up in, and only when
    # the booking moves (in time or to another room): a rename must not be
    # refused because an admin blocked the slot afterwards.
    if times_present &&
         (@sub_space_booking.times_changing? || @sub_space_booking.will_save_change_to_sub_space_id?) &&
         SubSpaceBooking
           .where(sub_space_id: @sub_space_booking.sub_space_id)
           .where(blocking: true)
           .where.not(id: @sub_space_booking.id)
           .overlapping(@sub_space_booking.start_time.utc, @sub_space_booking.end_time.utc)
           .any?
      flash[:alert] = "This time slot is already booked."
      respond_to do |format|
        format.json do
          render json: {
                   errors: ["TimeSlot This time slot is already booked."]
                 },
                 status: :unprocessable_content
        end
        format.html { redirect_to sub_space_booking_edit_path }
      end

      return
    end

    sub_space = @sub_space_booking.sub_space
    duration = times_present ? (@sub_space_booking.end_time - @sub_space_booking.start_time) / 1.hour : 0

    # The limits only matter when the booking's times move; renaming a booking
    # must not be blocked because a room's limits were lowered since. Minute
    # precision, the same test as the model's past-date rule.
    times_changed = times_present && @sub_space_booking.times_changing?

    max_duration = sub_space.maximum_booking_duration
    if !max_duration.nil? && !@user.admin? && times_changed && duration > max_duration
      render_update_limit_error(
        "DurationHour",
        "You cannot book #{sub_space.name} for more than #{max_duration} hours."
      )
      return
    end

    max_per_week = sub_space.maximum_booking_hours_per_week
    if !max_per_week.nil? && !@user.admin? && times_changed &&
         weekly_booked_hours(@sub_space_booking) + duration > max_per_week
      render_update_limit_error(
        "DurationWeek",
        "You cannot book #{sub_space.name} for more than #{max_per_week} hours per week."
      )
      return
    end

    if @sub_space_booking.update(sub_space_booking_update_params)
      flash[:notice] = "Successfully updated booking"
      respond_to do |format|
        format.json { render json: { status: "ok" }, status: :ok }
        format.html do
          redirect_to sub_space_booking_index_path(
                        anchor: "booking-calendar-tab",
                        room: @sub_space_booking.sub_space_id
                      )
        end
      end
    else
      respond_to do |format|
        format.json do
          render json: { errors: @sub_space_booking.errors.full_messages },
                 status: :unprocessable_content
        end
        format.html do
          flash.now[:alert] = @sub_space_booking.errors.full_messages.join(", ")
          render "edit"
        end
      end
    end
  end

  def approve
    sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    unless sub_space_booking.pending?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: "Booking for #{sub_space_booking.sub_space.name} is no longer pending."
      return
    end

    # 1. Update status
    sub_space_booking.change_status!(BookingStatus.approved)
    
    # 2. Stamp the approval with update_columns, so a row that no longer passes
    # some validation can still be approved. It writes only the approval
    # columns, never the times, so the past-date rule (it checks only
    # saves that set or move the times) allows approving a past pending booking.
    sub_space_booking.update_columns(
      approved_at: DateTime.now,
      approved_by_id: current_user.id
    )

    # 3. Pass the integer ID to align with expected enqueued job arguments
    BookingMailer.send_booking_approved(sub_space_booking.id).deliver_later

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: "Booking for #{sub_space_booking.sub_space.name} approved successfully."
  end

  def decline
    sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    unless sub_space_booking.pending?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: "Booking for #{sub_space_booking.sub_space.name} is no longer pending."
      return
    end

    sub_space_booking.change_status!(BookingStatus.declined)
    
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: "Booking for #{sub_space_booking.sub_space.name} declined successfully."
  end

  def bulk_approve_decline
    if params[:sub_space_booking_ids].blank?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"), alert: "No bookings selected."
      return
    end

    bulk_status = params[:bulk_status]

    unless %w[approve decline].include?(bulk_status)
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: "Failed to bulk update booking status."
      return
    end

    booking_ids = apply_bulk_booking_status(bulk_status)

    booking_ids.each { |id| BookingMailer.send_booking_approved(id).deliver_later } if bulk_status == "approve"
    skipped = Array(params[:sub_space_booking_ids]).uniq.size - booking_ids.size
    set_bulk_result_flash(
      booking_ids.size,
      skipped,
      notice: bulk_status == "approve" ? "Bookings approved successfully." : "Bookings declined successfully.",
      alert: "#{skipped} selected booking(s) were no longer pending and were skipped."
    )

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab")
  end

  def publish
    booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    booking.public = !booking.public
    booking.save
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice:
                  "Booking made #{booking.public ? "public" : "private"} successfully."
  end

  def delete
    unless current_user.admin? ||
             SubSpaceBooking.find(params[:sub_space_booking_id]).user_id ==
               current_user.id
      return(
        redirect_to root_path,
                    alert: "You are not authorized to view this page."
      )
    end

    booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    subspaceName = booking.sub_space.name
    booking.destroy_with_status!
    redirect_to sub_space_booking_index_path(anchor: "booking-tab"),
                notice: "Booking for #{subspaceName} deleted successfully."
  end

  def delete_remaining_recurring
    booking = SubSpaceBooking.find(params[:id])
    unless current_user.admin? || booking.user_id == current_user.id
      return(
        redirect_to root_path,
                    alert: "You are not authorized to view this page."
      )
    end

    unless booking.recurring_booking.present?
      return(
        redirect_to sub_space_booking_index_path(anchor: "booking-tab"),
                    notice: "Booking is not attached to a recurring booking."
      )
    end

    subspaceName = booking.sub_space.name
    # Get this and rest of bookings
    # NOTE: if booking.recurring_booking is ever somehow null
    # the whole table would get destroyed :^)
    remaining_bookings =
      SubSpaceBooking.where(recurring_booking: booking.recurring_booking).where(
        start_time: booking.start_time..
      ) # endless range
    # Is a transaction necessary here?
    ActiveRecord::Base.transaction do
      remaining_bookings.each(&:destroy_with_status!)
    end
    redirect_to sub_space_booking_index_path(anchor: "booking-tab"),
                notice:
                  "Remaining bookings for #{subspaceName} deleted successfully."
  end

  def get_sub_space_booking
    sub_space_booking = SubSpaceBooking.find(params[:id])
    render json: { **sub_space_booking.as_json }
  end

  private

  # Only staff and admins may fetch a booking's details (get_sub_space_booking),
  # so the calendar feed tells the page whether a click can open one.
  def viewer_may_open_details
    @user.admin? || @user.staff?
  end

  # A booking for one occurrence, owned by the current user, whose past-date
  # check uses the request's single clock read.
  def new_occurrence(attrs, now)
    booking = SubSpaceBooking.new(attrs)
    booking.user_id = current_user.id
    booking.reference_time = now
    booking
  end

  # A series may span at most 365 days from its first start to recurring_end
  # (a cap on the series length). With weekly
  # as the densest frequency that is at most 54 occurrences.
  SERIES_MAX_DAYS = 365

  # recurring_end as a Date, or nil when it is missing or malformed.
  def series_end_date
    raw = params[:sub_space_booking][:recurring_end]
    Date.parse(raw.to_s) if raw.present?
  rescue Date::Error
    nil
  end

  # Books every occurrence that does not start in the past, all in one
  # RecurringBooking group, and renders once at the end. If the first
  # occurrence that is not in the past cannot be booked, the series is refused
  # and nothing is saved.
  # A later failed occurrence does not stop the rest (a partial series is
  # kept and reported). The mail goes out for the first occurrence actually
  # booked.
  def book_series(attrs, occurrences, now)
    recurring_booking = RecurringBooking.new
    booked = 0
    last_booked = nil
    failures = [] # [date, failure]
    occurrences.each do |start_time, end_time|
      booking = new_occurrence(attrs.merge(start_time: start_time, end_time: end_time), now)
      next if SubSpaceBooking.start_in_past?(booking.start_time, now)

      failure = book_occurrence(booking, recurring_booking: recurring_booking, send_email: booked.zero?)
      if failure
        return render_first_occurrence_refused(booking, failure) if booked.zero?

        failures << [booking.start_time.to_date.iso8601, failure]
      else
        booked += 1
        last_booked = booking
      end
    end

    render_series_result(failures, booked, last_booked)
  end

  def render_series_result(failures, booked, last_booked)
    if failures.any?
      render_series_failure(failures, booked)
    elsif booked.zero? # every occurrence was in the past
      message = SubSpaceBooking.past_start_message
      render_booking_failure(errors: [message], alert: message)
    else
      render_booking_success(last_booked.sub_space)
    end
  end

  # Checks one occurrence on the unsaved record, then saves it with its status
  # in one transaction, so a failure leaves no half-made row. Renders nothing:
  # returns nil when booked, or a failure ({ errors:, alert:, timeslot: }) for
  # the caller to render.
  def book_occurrence(booking, recurring_booking: nil, send_email: true)
    return invalid_booking_failure(booking) unless booking.valid_without_status?

    sub_space = booking.sub_space

    # the zoned instants the model stores, compared with the stored UTC
    # instants of the blocks (half-open overlap).
    if !booking.blocking &&
        SubSpaceBooking
          .where(sub_space_id: sub_space.id)
          .where(blocking: true)
          .overlapping(booking.start_time.utc, booking.end_time.utc)
          .any?
      return { errors: ["TimeSlot This time slot is already booked."],
               alert: "This time slot is already booked.", timeslot: true }
    end

    # Check time violations
    duration = (booking.end_time - booking.start_time) / 1.hour
    if !sub_space.maximum_booking_duration.nil? && !current_user.admin? &&
         duration > sub_space.maximum_booking_duration
      return limit_failure("DurationHour",
                           "You cannot book #{sub_space.name} for more than #{sub_space.maximum_booking_duration} hours.")
    end

    if !sub_space.maximum_booking_hours_per_week.nil? && !current_user.admin? &&
         weekly_booked_hours(booking) + duration > sub_space.maximum_booking_hours_per_week
      return limit_failure(
        "DurationWeek",
        "You cannot book #{sub_space.name} for more than #{sub_space.maximum_booking_hours_per_week} hours per week."
      )
    end

    status =
      # Auto-approve bookings made by admins
      if current_user.admin?
        BookingStatus.approved
      elsif sub_space.approval_required
        if sub_space.max_automatic_approval_hour.nil?
          BookingStatus.pending
        elsif duration <= sub_space.max_automatic_approval_hour
          BookingStatus.approved
        else
          BookingStatus.pending
        end
      else
        BookingStatus.approved
      end

    booking.public = sub_space.default_public
    booking.recurring_booking = recurring_booking # Attach the RecurringBooking handle, is saved with the booking itself
    # Set approved_at and approved_by for admin bookings
    if current_user.admin? && status == BookingStatus.approved
      booking.approved_at = DateTime.now
      booking.approved_by_id = current_user.id
    end

    booking.save_with_status!(status)

    send_booking_created_mail(booking) if send_email
    nil
  rescue ActiveRecord::RecordInvalid => e
    invalid_booking_failure(e.record)
  end

  def invalid_booking_failure(record)
    { errors: record.errors.full_messages, alert: record.errors.full_messages.join(", ") }
  end

  def limit_failure(code, message)
    { errors: ["#{code} #{message}"], alert: message }
  end

  def send_booking_created_mail(booking)
    if booking.pending?
      BookingMailer.send_booking_needs_approval(booking.id).deliver_later
    elsif booking.approved?
      # Send appropriate confirmation for approved bookings
      if current_user.admin?
        BookingMailer.send_booking_approved(booking.id).deliver_later
      else
        BookingMailer.send_booking_automatically_approved(booking.id).deliver_later
        BookingMailer.send_booking_approved(booking.id).deliver_later
      end
    end
  end

  def booking_calendar_path
    sub_space_booking_index_path(anchor: "booking-calendar-tab",
                                 room: params[:sub_space_booking][:sub_space_id])
  end

  # JSON: 422 with the errors (a timeslot conflict also leaves the flash alert,
  # as before). HTML: back to the room's calendar with the alert.
  def render_booking_failure(failure)
    respond_to do |format|
      format.json do
        flash[:alert] = failure[:alert] if failure[:timeslot]
        render json: { errors: failure[:errors] }, status: :unprocessable_content
      end
      format.html { redirect_to booking_calendar_path, alert: failure[:alert] }
    end
  end

  # The first occurrence failed, so no occurrence was booked: 422 with the
  # failure's errors, as for a single booking, and a message that says the
  # series was not created.
  def render_first_occurrence_refused(booking, failure)
    summary = I18n.t("sub_space_booking.series.first_failed",
                     date: booking.start_time.to_date.iso8601, reason: failure[:alert])
    respond_to do |format|
      format.json do
        flash[:alert] = summary
        render json: { errors: failure[:errors], summary: summary }, status: :unprocessable_content
      end
      format.html { redirect_to booking_calendar_path, alert: summary }
    end
  end

  # A partial series is kept, so the answer says what happened: 422 (not
  # every occurrence was booked) with the first failure's errors, as before,
  # plus how many were booked and the dates that were not. No success notice.
  def render_series_failure(failures, booked)
    failed_dates = failures.map(&:first)
    summary = I18n.t("sub_space_booking.series.partial",
                     booked: booked, total: booked + failures.size, failed: failed_dates.join(", "))
    respond_to do |format|
      format.json do
        flash[:alert] = summary
        render json: { errors: failures.first.last[:errors], booked: booked, failed: failed_dates,
                       summary: summary },
               status: :unprocessable_content
      end
      format.html { redirect_to booking_calendar_path, alert: summary }
    end
  end

  # JSON: an empty 204, as before (the page refetches the calendar). HTML:
  # back to the room's calendar with the notice (there is no create template).
  def render_booking_success(sub_space)
    flash[:notice] = "Booking for #{sub_space.name} created successfully."
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to booking_calendar_path }
    end
  end

  # Hours the booking's owner already has in the booking's sub space, in the week
  # (Time.zone) containing the booking's start_time, not counting the booking itself.
  def weekly_booked_hours(booking)
    week = booking.start_time.in_time_zone.all_week
    SubSpaceBooking
      .where(sub_space_id: booking.sub_space_id, user_id: booking.user_id)
      .where.not(id: booking.id)
      .where(start_time: week)
      .sum { |other| other.end_time - other.start_time } / 1.hour
  end

  def render_update_limit_error(code, message)
    respond_to do |format|
      format.json do
        render json: { errors: ["#{code} #{message}"] },
               status: :unprocessable_content
      end
      format.html do
        redirect_to sub_space_booking_edit_path, alert: message
      end
    end
  end

  def grant_booking_access!(uba)
    uba.identity = "Other" unless %w[JMTS Staff GNG Other].include?(uba.identity)
    uba.date ||= Time.now
    UserBookingApproval.transaction do
      uba.update!(approved: true, staff: current_user)
      uba.user.update!(booking_approval: true)
    end
    uba.id
  end

  def access_request_recipients(identity)
    case identity
    when "JMTS" then jmts_access_request_recipients
    when "Staff" then staff_access_request_recipients
    when "GNG" then ["makerlab@uottawa.ca"]
    else [BookingMailer::MTC_MAILBOX]
    end
  end

  def jmts_access_request_recipients
    jmts = Space.find_by(name: "JMTS")
    if jmts.nil?
      Rails.error.report(
        RuntimeError.new('Booking access request for JMTS, but no space named "JMTS" exists; using the default recipients'),
        handled: true,
        severity: :warning
      )
    end
    emails = jmts ? jmts.space_managers.map(&:email) : []
    emails.empty? ? [BookingMailer::MTC_MAILBOX] : emails
  end

  # Returns nil (after setting the alert) when no staff supervisor was chosen.
  def staff_access_request_recipients
    supervisor = User.find_by(id: params[:supervisor]) if params[:supervisor].present?
    if supervisor.nil? || !supervisor.staff?
      flash[:alert] = "Please choose a staff member as your supervisor."
      return nil
    end
    [supervisor.email]
  end

  def grant_pending_access(ids)
    approved_ids = []
    UserBookingApproval.transaction do
      UserBookingApproval
        .where(id: ids)
        .reject { |uba| uba.approved? && uba.user.booking_approval? }
        .each { |uba| approved_ids << grant_booking_access!(uba) }
    end
    approved_ids
  end

  # Only bookings that are still pending are changed; returns their ids.
  def apply_bulk_booking_status(bulk_status)
    booking_ids = []
    SubSpaceBooking.transaction do
      pending = SubSpaceBooking.pending.includes(sub_space_booking_status: :booking_status).where(id: params[:sub_space_booking_ids]).to_a
      booking_ids = pending.map(&:id)

      if bulk_status == "approve"
        SubSpaceBooking.change_status_of!(pending, BookingStatus.approved)
        # update_all bypasses validations identically to update_columns
        SubSpaceBooking.where(id: booking_ids).update_all(
          approved_at: DateTime.now,
          approved_by_id: current_user.id
        )
      else
        SubSpaceBooking.change_status_of!(pending, BookingStatus.declined)
      end
    end
    booking_ids
  end

  # Notice when something was applied (all_notice when nothing was skipped), alert when something was skipped.
  def set_bulk_result_flash(applied, skipped, notice:, alert:, all_notice: notice)
    flash[:notice] = skipped.positive? ? notice : all_notice if applied.positive?
    flash[:alert] = alert if skipped.positive?
  end

  def approval_failed(error)
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                alert: "Failed to approve: #{error.record.errors.full_messages.join(", ")}"
  end

  def load_recurring_bookings_for_page(paginated_bookings)
    # Get unique recurring_booking_ids from current page
    recurring_ids = paginated_bookings.map(&:recurring_booking_id).compact.uniq
    
    @recurring_bookings_map = {}
    
    return if recurring_ids.empty?
    
    # Load ALL pending bookings for these recurring groups (not just current page)
    # Use the same timestamp as the main query to avoid timing issues
    all_recurring_bookings = SubSpaceBooking
      .pending
      .includes(:user, sub_space: :space)
      .where(recurring_booking_id: recurring_ids)
      .where('sub_space_bookings.end_time > ?', @current_time)
      .order(start_time: :asc)
    
    # Group them by recurring_booking_id
    @recurring_bookings_map = all_recurring_bookings.group_by(&:recurring_booking_id)
  end

  # The pending and approved bookings of the room, which are the ones the
  # calendar shows. A booking without a status is neither, so it is not listed.
  def feed_bookings
    SubSpaceBooking
      .where(sub_space_id: params[:room])
      .joins(:user)
      .where(booking_status_id: [BookingStatus.approved.id, BookingStatus.pending.id])
      .includes(:user)
      .order(:id)
  end

  def feed_event(booking)
    {
      id: "booking_#{booking.id}_#{booking.sub_space_id}",
      title: feed_title(booking),
      start: booking.start_time,
      end: booking.end_time,
      color: booking.color(@user.id),
      viewable: @viewer_may_open_details
    }
  end

  def feed_title(booking)
    return "Space Blocked" if blocked_for_viewer?(booking)

    title = details_visible?(booking) ? "#{booking.name} - #{booking.description}" : "Space Booked"
    title += " (Pending)" if booking.pending?
    title += " - #{booking.user.name}" if @user.admin? && booking.user != @user
    title
  end

  def blocked_for_viewer?(booking)
    booking.blocking && !booking.public && (!@user.admin? || booking.user != @user)
  end

  def details_visible?(booking)
    @user.admin? || booking.user == @user || booking.public
  end

  def current_bookings(booking_status_id, page_key: "pending_page")
    scope = SubSpaceBooking
              .where(booking_status_id: booking_status_id)
              .where("sub_space_bookings.end_time > ?", @current_time)
              .includes(:user, sub_space: :space)
              .order(start_time: :asc)

    pagy(scope, page_key: page_key, limit: 15)
  end

  def old_bookings(booking_status_id, page_key: "old_approved_page")
    scope = SubSpaceBooking
              .where(booking_status_id: booking_status_id)
              .where("sub_space_bookings.end_time < ?", @current_time)
              .includes(:user, sub_space: :space)
              .order(start_time: :desc)

    pagy(scope, page_key: page_key, limit: 15)
  end

  def user_account
    return if signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
    
  end
  def user_approved
    return if current_user.booking_approval || current_user.admin?
      redirect_to root_path,
                  alert: "You must be approved to book to view this page."
    
  end
  def user_admin_or_staff
    return if current_user.admin? || current_user.staff?
      redirect_to root_path,
                  alert: "You must be an admin or staff to view this page."
    
  end
  def user_admin
    return if current_user.admin?
      redirect_to root_path, alert: "You must be an admin to view this page."
    
  end
  def user_booking_belongs
    unless SubSpaceBooking.find(params[:sub_space_booking_id]).user_id ==
             current_user.id || current_user.admin?
      redirect_to root_path,
                  alert:
                    "You must be the owner of this booking or an admin to delete it."
    end
  end

  def sub_space_booking_params
    params.require(:sub_space_booking).permit(
      :start_time,
      :end_time,
      :name,
      :description,
      :sub_space_id,
      :blocking
    )
  end

  # blocking and sub_space_id are create-time/admin decisions: only admins may
  # change them on an existing booking.
  def sub_space_booking_update_params
    permitted = %i[start_time end_time name description]
    permitted += %i[sub_space_id blocking] if current_user.admin?
    # A blank start/end means "unchanged": the stored times stay.
    params.require(:sub_space_booking).permit(*permitted)
          .reject { |key, value| %w[start_time end_time].include?(key) && value.blank? }
  end
end
