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
    @subspace = SubSpace.find(params[:room]) if params[:room].present?
    @bookings =
      SubSpaceBooking
        .where(user_id: current_user.id)
        .joins(:user)
        .includes(:sub_space)
        .order(start_time: :desc)

    load_admin_queues if current_user.admin?
    @supervisors = SpaceManagerJoin.supervisor_options
  end

  def request_access
    if params[:comments].blank?
      flash[:alert] = t("sub_space_booking.messages.reason_missing")
      redirect_to root_path
      return
    end

    emails = access_request_recipients(params[:identity])
    if emails.nil?
      redirect_to root_path
      return
    end

    booking_approval = current_user.request_booking_access(comments: params[:comments], identity: params[:identity])
    if booking_approval.persisted?
      BookingMailer.send_booking_approval_request_sent(booking_approval.id, emails).deliver_later
      flash[:notice] = t("sub_space_booking.messages.access_requested")
    else
      flash[:alert] = access_request_refusal(booking_approval)
    end
    redirect_to root_path
  end

  def approve_access
    if params[:id].nil?
      user = User.find(params[:user_id])
      id = user.approve_booking_access(by: current_user)
      granted_notice = t("sub_space_booking.messages.access_granted")
    else
      request = UserBookingApproval.find(params[:id])
      user = request.user
      id = user.approve_booking_access(by: current_user, request_id: request.id)
      granted_notice = t("sub_space_booking.messages.access_request_approved")
    end
    if id.nil?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  notice: t("sub_space_booking.messages.already_has_access", name: user.name)
    else
      BookingMailer.send_booking_approval_request_approved(id).deliver_later
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"), notice: granted_notice
    end
  rescue ActiveRecord::RecordInvalid => e
    approval_failed(e)
  end

  # Declines a pending request or revokes an approved one; the request is kept with its status,
  # and the requester is mailed once the decision is saved.
  def deny_access
    approval = UserBookingApproval.find(params[:id])
    approval.user.deny_booking_access(approval, by: current_user, reason: params[:reason].to_s.strip.presence)
    BookingMailer.send_booking_access_denied(approval.id).deliver_later
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: t(approval.revoked? ? "sub_space_booking.messages.access_revoked" :
                                              "sub_space_booking.messages.access_request_declined")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                alert: validation_message(e.record, "failed_saves.booking_decline")
  end

  def bulk_approve_access
    if params[:user_booking_approval_ids].blank?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: t("sub_space_booking.messages.no_approvals_selected")
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
      notice: t("sub_space_booking.bulk.access_approved"),
      all_notice: t("sub_space_booking.bulk.access_all_approved"),
      alert: t("sub_space_booking.bulk.access_skipped", count: skipped)
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
    return refuse_blocking if blocking_refused?(attrs)

    booking = new_occurrence(attrs, now)
    booking.valid_without_status?
    # A recurring series skips its past occurrences instead of failing, so a
    # past first occurrence is not an error yet (see book_series).
    booking.errors.delete(:start_time, :in_the_past) if recurring
    return render_booking_failure(invalid_booking_failure(booking)) if booking.errors.any?

    recurring ? create_series(attrs, booking, now) : create_single(booking)
  end

  def edit
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    if (
         @sub_space_booking.pending? && !@user.admin? &&
           !@user.eql?(@sub_space_booking.user)
       ) || (@sub_space_booking.approved? && !@user.admin?)
      redirect_to sub_space_booking_index_path,
                  alert: t("sub_space_booking.messages.edit_refused")
    end
  end

  def update
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    return refuse_approved_edit if @sub_space_booking.approved? && !@user.admin?

    # Check the overlap and the limits against the values the model will store
    # (zoned, the user's own offsets included), not against a re-parsed copy of
    # the raw params. A blank start/end is not sent on (the stored
    # times stay); an unparseable one leaves the time nil, and the model's
    # presence check answers it.
    @sub_space_booking.assign_attributes(sub_space_booking_update_params)
    refusal = update_refusal(@sub_space_booking)
    return render_update_limit_error(refusal) if refusal

    if @sub_space_booking.update(sub_space_booking_update_params)
      render_updated
    else
      render_update_invalid
    end
  end

  def approve
    sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    unless sub_space_booking.approve_if_pending!(by: current_user)
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: t("sub_space_booking.messages.no_longer_pending", room: sub_space_booking.sub_space.name)
      return
    end

    BookingMailer.send_booking_approved(sub_space_booking.id).deliver_later

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: t("sub_space_booking.messages.approved", room: sub_space_booking.sub_space.name)
  end

  def decline
    sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    unless sub_space_booking.decline_if_pending!
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: t("sub_space_booking.messages.no_longer_pending", room: sub_space_booking.sub_space.name)
      return
    end

    BookingMailer.send_booking_declined(sub_space_booking.id).deliver_later

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: t("sub_space_booking.messages.declined", room: sub_space_booking.sub_space.name)
  end

  def bulk_approve_decline
    if params[:sub_space_booking_ids].blank?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: t("sub_space_booking.messages.no_bookings_selected")
      return
    end

    bulk_status = params[:bulk_status]

    unless %w[approve decline].include?(bulk_status)
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: t("errors.bookings.bulk_status_invalid")
      return
    end

    booking_ids = apply_bulk_booking_status(bulk_status)

    mail_bulk_result(bulk_status, booking_ids)
    skipped = Array(params[:sub_space_booking_ids]).uniq.size - booking_ids.size
    set_bulk_result_flash(
      booking_ids.size,
      skipped,
      notice: t(bulk_status == "approve" ? "sub_space_booking.bulk.bookings_approved" : "sub_space_booking.bulk.bookings_declined"),
      alert: t("sub_space_booking.bulk.bookings_skipped", count: skipped)
    )

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab")
  end

  def publish
    booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    booking.public = !booking.public
    booking.save
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: t(booking.public ? "sub_space_booking.messages.made_public" :
                                           "sub_space_booking.messages.made_private")
  end

  # Only the owner or an admin gets here (user_booking_belongs).
  def delete
    booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    subspaceName = booking.sub_space.name
    booking.destroy_with_status!
    render_deleted(t("sub_space_booking.messages.deleted", room: subspaceName))
  end

  def delete_remaining_recurring
    booking = SubSpaceBooking.find(params[:id])
    unless current_user.admin? || booking.user_id == current_user.id
      return(
        redirect_to root_path,
                    alert: t("sub_space_booking.messages.not_authorized")
      )
    end

    unless booking.recurring_booking.present?
      return(
        redirect_to sub_space_booking_index_path(anchor: "booking-tab"),
                    notice: t("sub_space_booking.messages.not_recurring")
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
    render_deleted(t("sub_space_booking.messages.remaining_deleted", room: subspaceName))
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

  # A delete from the booking page's fetch (JSON) is answered 204 and the page reloads to show the notice; any other
  # request is redirected to the bookings list.
  def render_deleted(notice)
    flash[:notice] = notice
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to sub_space_booking_index_path(anchor: "booking-tab") }
    end
  end

  def blocking_refused?(attrs)
    ActiveModel::Type::Boolean.new.cast(attrs[:blocking]) && !current_user.admin?
  end

  def refuse_blocking
    message = t("sub_space_booking.messages.blocking_refused")
    respond_to do |format|
      format.json do
        render json: { errors: [message] }, status: :forbidden
      end
      format.html do
        flash[:alert] = message
        redirect_to sub_space_booking_index_path
      end
    end
  end

  def create_single(booking)
    failure = book_occurrence(booking)
    if failure
      render_booking_failure(failure)
    else
      render_booking_success(booking.sub_space)
    end
  end

  # The first occurrence passed the record's own checks; the series still needs
  # a frequency and an end date at most SERIES_MAX_DAYS after its first day.
  def create_series(attrs, first, now)
    end_date = series_end_date # nil when missing or malformed
    frequency = params[:sub_space_booking][:recurring_frequency]
    refusal = series_refusal(first, end_date, frequency)
    return render_booking_failure(refusal) if refusal

    book_series(attrs, BookingSeries.new(first.start_time, first.end_time, end_date, frequency), now)
  end

  def series_refusal(first, end_date, frequency)
    if end_date.nil? || frequency.blank?
      series_failure(t("errors.bookings.recurring_invalid"))
    elsif end_date > first.start_time.to_date + SERIES_MAX_DAYS.days
      series_failure(I18n.t("sub_space_booking.series.too_long", days: SERIES_MAX_DAYS))
    end
  end

  def series_failure(message)
    { errors: ["Recurring #{message}"], alert: message }
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
  rescue ArgumentError
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

  # Checks one occurrence against the room's blocks and limits, then saves it
  # with its status in one transaction, so a failure leaves no half-made row.
  # The record's own checks already passed in create: a series occurrence
  # differs from the first only by its date, and past ones are skipped; save!
  # still runs them. Renders nothing:
  # returns nil when booked, or a failure ({ errors:, alert: }) for
  # the caller to render.
  def book_occurrence(booking, recurring_booking: nil, send_email: true)
    failure = occurrence_refusal(booking)
    return failure if failure

    booking.apply_initial_state(by: current_user)
    booking.recurring_booking = recurring_booking # Attach the RecurringBooking handle, is saved with the booking itself
    booking.save!

    send_booking_created_mail(booking) if send_email
    nil
  rescue ActiveRecord::RecordInvalid => e
    invalid_booking_failure(e.record)
  end

  # A new booking may not overlap a block unless it is a block itself, and only
  # admins may break the room's limits.
  def occurrence_refusal(booking)
    return slot_taken_failure if !booking.blocking && booking.overlaps_block?

    room_limit_failure(booking) unless current_user.admin?
  end

  def slot_taken_failure
    limit_failure("TimeSlot", t("sub_space_booking.limits.slot_taken"))
  end

  # The first of its room's limits the booking breaks, or nil: the maximum
  # duration, then the owner's maximum hours in the room that week.
  def room_limit_failure(booking)
    room = booking.sub_space
    if booking.exceeds_maximum_duration?
      limit_failure("DurationHour",
                    t("sub_space_booking.limits.maximum_duration", room: room.name, hours: room.maximum_booking_duration))
    elsif booking.exceeds_weekly_hours?
      limit_failure("DurationWeek", t("sub_space_booking.limits.weekly_hours",
                                      room: room.name, hours: room.maximum_booking_hours_per_week))
    end
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
    else # approved: a new booking is saved as pending or approved
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

  # JSON: 422 with the errors (the page shows them without reloading, so no
  # flash is set). HTML: back to the room's calendar with the alert.
  def render_booking_failure(failure)
    respond_to do |format|
      format.json do
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
        render json: { errors: failures.first.last[:errors], booked: booked, failed: failed_dates,
                       summary: summary },
               status: :unprocessable_content
      end
      format.html { redirect_to booking_calendar_path, alert: summary }
    end
  end

  # JSON: an empty 204, as before (the page reloads to show the notice). HTML:
  # back to the room's calendar with the notice (there is no create template).
  def render_booking_success(sub_space)
    flash[:notice] = t("sub_space_booking.messages.created", room: sub_space.name)
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to booking_calendar_path }
    end
  end

  def render_update_limit_error(failure)
    respond_to do |format|
      format.json do
        render json: { errors: failure[:errors] },
               status: :unprocessable_content
      end
      format.html do
        redirect_to sub_space_booking_edit_path, alert: failure[:alert]
      end
    end
  end

  # The overlap is checked in the room the booking ends up in, and only when
  # the booking moves (in time or to another room): a rename must not be
  # refused because an admin blocked the slot afterwards. The limits only
  # matter when the booking's times move; renaming a booking must not be
  # blocked because a room's limits were lowered since. Minute precision, the
  # same test as the model's past-date rule. A missing time is no refusal: the
  # model's presence check answers it. Returns a failure ({ errors:, alert: }) or nil.
  def update_refusal(booking)
    return slot_taken_failure if booking.moving? && booking.overlaps_block?

    room_limit_failure(booking) if !@user.admin? && booking.times_changing?
  end

  def refuse_approved_edit
    redirect_to sub_space_booking_index_path(
                  anchor: "booking-calendar-tab",
                  room: @sub_space_booking.sub_space_id
                ),
                alert: t("sub_space_booking.messages.approved_edit_refused")
  end

  def render_updated
    respond_to do |format|
      format.json { render json: { status: "ok" }, status: :ok }
      format.html do
        redirect_to sub_space_booking_index_path(
                      anchor: "booking-calendar-tab",
                      room: @sub_space_booking.sub_space_id
                    ),
                    notice: t("sub_space_booking.messages.updated")
      end
    end
  end

  def render_update_invalid
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
      flash[:alert] = t("sub_space_booking.messages.supervisor_missing")
      return nil
    end
    [supervisor.email]
  end

  # Users are locked in id order so two bulk approvals cannot wait on each other.
  def grant_pending_access(ids)
    UserBookingApproval.transaction do
      UserBookingApproval
        .where(id: ids)
        .reorder(:user_id, :id)
        .filter_map { |uba| uba.user.approve_booking_access(by: current_user, request_id: uba.id) }
    end
  end

  # Only bookings that are still pending are changed; returns their ids.
  def apply_bulk_booking_status(bulk_status)
    booking_ids = []
    SubSpaceBooking.transaction do
      pending = SubSpaceBooking.pending.where(id: params[:sub_space_booking_ids]).to_a

      if bulk_status == "approve"
        booking_ids = pending.map(&:id)
        SubSpaceBooking.change_status_of!(pending, BookingStatus.approved)
        # update_all bypasses validations identically to update_columns
        SubSpaceBooking.where(id: booking_ids).update_all(
          approved_at: DateTime.now,
          approved_by_id: current_user.id
        )
      else
        booking_ids = pending.select(&:decline_if_pending!).map(&:id)
      end
    end
    booking_ids
  end

  # Queues the booker's mail for each booking the bulk action changed.
  def mail_bulk_result(bulk_status, booking_ids)
    mailer_method = bulk_status == "approve" ? :send_booking_approved : :send_booking_declined
    booking_ids.each { |id| BookingMailer.public_send(mailer_method, id).deliver_later }
  end

  # Notice when something was applied (all_notice when nothing was skipped), alert when something was skipped.
  def set_bulk_result_flash(applied, skipped, notice:, alert:, all_notice: notice)
    flash[:notice] = skipped.positive? ? notice : all_notice if applied.positive?
    flash[:alert] = alert if skipped.positive?
  end

  # The request was refused (access already held or already pending, said as is on the base) or failed
  # validation (the fields are named after the translated sentence).
  def access_request_refusal(booking_approval)
    return booking_approval.errors.full_messages.join(", ") if booking_approval.errors.include?(:base)

    validation_message(booking_approval, "errors.bookings.access_request_failed")
  end

  def approval_failed(error)
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                alert: validation_message(error.record, "errors.bookings.access_approve_failed")
  end

  def load_admin_queues
    @current_time = Time.now

    @pagy_pending, @pending_bookings = current_bookings(BookingStatus.pending.id, page_key: "pending_page")
    load_recurring_bookings_for_page(@pending_bookings)

    @pagy_approved, @approved_bookings = current_bookings(BookingStatus.approved.id, page_key: "approved_page")
    @pagy_declined, @declined_bookings = current_bookings(BookingStatus.declined.id, page_key: "declined_page")
    @pagy_old_pending, @old_pending_bookings = old_bookings(BookingStatus.pending.id, page_key: "old_pending_page")
    @pagy_old_approved, @old_approved_bookings = old_bookings(BookingStatus.approved.id, page_key: "old_approved_page")
    @pagy_old_declined, @old_declined_bookings = old_bookings(BookingStatus.declined.id, page_key: "old_declined_page")
    @pending_access_requests = UserBookingApproval.pending.from_active_accounts.includes(:user).to_a
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
      .includes(sub_space: :space)
      .where(recurring_booking_id: recurring_ids)
      .where('sub_space_bookings.end_time > ?', @current_time)
      .order(start_time: :asc)
    
    # Group them by recurring_booking_id
    @recurring_bookings_map = all_recurring_bookings.group_by(&:recurring_booking_id)
  end

  # The pending and approved bookings of the room, which are the ones the
  # calendar shows. A booking without a status is neither, so it is not listed.
  # Bookings with no owner or a deleted owner are listed too: they still hold the room.
  # Owners are loaded, in one query, only for the entries whose title names them.
  def feed_bookings
    bookings = SubSpaceBooking
                 .where(sub_space_id: params[:room])
                 .where(booking_status_id: [BookingStatus.approved.id, BookingStatus.pending.id])
                 .order(:start_time, :id)
                 .to_a
    ActiveRecord::Associations::Preloader.new(records: bookings.select { |booking| owner_shown?(booking) },
                                              associations: :display_user).call
    bookings
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
    return t("sub_space_booking.feed.blocked") if blocked_for_viewer?(booking)

    title = details_visible?(booking) ? "#{booking.name} - #{booking.description}" : t("sub_space_booking.feed.booked")
    title = t("sub_space_booking.feed.pending", title: title) if booking.pending?
    owner = feed_owner_name(booking)
    title += " - #{owner}" if owner
    title
  end

  # Admins see who booked someone else's slot: nothing for a booking with no owner, and the
  # deleted-account wording for an owner whose account was deleted.
  def feed_owner_name(booking)
    helpers.staff_user_name(booking.display_user) if owner_shown?(booking)
  end

  def owner_shown?(booking)
    @user.admin? && !own_booking?(booking) && !blocked_for_viewer?(booking)
  end

  # The feed is for signed-in users only, so the viewer always has an id.
  def own_booking?(booking)
    booking.user_id == @user.id
  end

  def blocked_for_viewer?(booking)
    booking.blocking && !booking.public && (!@user.admin? || !own_booking?(booking))
  end

  def details_visible?(booking)
    @user.admin? || own_booking?(booking) || booking.public
  end

  def current_bookings(booking_status_id, page_key: "pending_page")
    scope = SubSpaceBooking
              .where(booking_status_id: booking_status_id)
              .where("sub_space_bookings.end_time > ?", @current_time)
              .includes(:display_user, sub_space: :space)
              .order(start_time: :asc)

    pagy(scope, page_key: page_key, limit: 15)
  end

  def old_bookings(booking_status_id, page_key: "old_approved_page")
    scope = SubSpaceBooking
              .where(booking_status_id: booking_status_id)
              .where("sub_space_bookings.end_time < ?", @current_time)
              .includes(:display_user, sub_space: :space)
              .order(start_time: :desc)

    pagy(scope, page_key: page_key, limit: 15)
  end

  def user_account
    return if signed_in?
      redirect_to login_path, alert: t("sub_space_booking.messages.login_required")
    
  end
  def user_approved
    return if current_user.booking_approval || current_user.admin?
      redirect_to root_path,
                  alert: t("sub_space_booking.messages.approval_required")
    
  end
  def user_admin_or_staff
    return if current_user.admin? || current_user.staff?
      redirect_to root_path,
                  alert: t("sub_space_booking.messages.staff_required")
    
  end
  def user_admin
    return if current_user.admin?
      redirect_to root_path, alert: t("sub_space_booking.messages.admin_required")
    
  end
  def user_booking_belongs
    unless SubSpaceBooking.find(params[:sub_space_booking_id]).user_id ==
             current_user.id || current_user.admin?
      redirect_to root_path,
                  alert:
                    t("sub_space_booking.messages.owner_required")
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
