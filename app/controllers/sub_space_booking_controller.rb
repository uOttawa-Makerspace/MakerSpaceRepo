class SubSpaceBookingController < SessionsController
  before_action :no_container
  before_action :user_account
  before_action :user_signed_in, only: %i[index request_access bookings]
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
        .includes(:sub_space, :sub_space_booking_status)
        .order(start_time: :desc)
    if current_user.admin?
      # Use a consistent timestamp for all queries
      # NOTE: this gives system time, set in config.time_zone
      # Keep it because we're using Time.zone elsewhere in this controller
      # https://thoughtbot.com/blog/its-about-time-zones
      @current_time = Time.now
      
      # Need to get the booking status from the sub space booking status table for the booking
      @pending_bookings = current_bookings(BookingStatus::PENDING.id)
      
      load_recurring_bookings_for_page(@pending_bookings)
      
      @approved_bookings = current_bookings(BookingStatus::APPROVED.id)
      @declined_bookings = current_bookings(BookingStatus::DECLINED.id)
      @old_pending_bookings = old_bookings(BookingStatus::PENDING.id)
      @old_approved_bookings = old_bookings(BookingStatus::APPROVED.id)
      @old_declined_bookings = old_bookings(BookingStatus::DECLINED.id)
    end

    @supervisors = []
    SpaceManagerJoin.all.each do |smj|
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
        emails = []

        case params[:identity]
        when "JMTS"
          jmts = Space.find_by(name: "JMTS")
          jmts.space_managers.each { |sm| emails << sm.email }
        when "Staff"
          emails << User.find(params[:supervisor]).email
        when "GNG"
          emails << "makerlab@uottawa.ca"
        else
          emails << "mtc@uottawa.ca"
        end

        BookingMailer.send_booking_approval_request_sent(
          booking_approval.id,
          emails
        ).deliver_now

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
      uba =
        UserBookingApproval.new(
          user: user,
          date: Time.now,
          approved: true,
          staff: current_user
        )
      uba.save
      user.update(booking_approval: true)
      user.save!
      BookingMailer.send_booking_approval_request_approved(uba.id).deliver_now
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab")
    else
      user = UserBookingApproval.find(params[:id]).user
      uba = UserBookingApproval.find(params[:id])
      uba.update(approved: true, staff_id: current_user.id)
      user.update(booking_approval: true)
      user.save!
      BookingMailer.send_booking_approval_request_approved(uba.id).deliver_now
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  notice: "Access request approved successfully."
    end
  end

  def deny_access
    user = UserBookingApproval.find(params[:id]).user
    UserBookingApproval.find(params[:id]).destroy
    user.booking_approval = false
    user.save!
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: "Access request declined successfully."
  end

  def bulk_approve_access
    # set identity to 'Regular' if it's null
    identity = params[:identity].presence || "Regular"

    if params[:user_booking_approval_ids].blank?
      redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                  alert: "No approvals selected."
      return
    end

    UserBookingApproval
      .where(id: params[:user_booking_approval_ids])
      .each do |uba|
        uba.assign_attributes(
          approved: true,
          staff_id: current_user.id,
          identity: identity
        )
        if uba.save
          uba.user.update!(booking_approval: true)
          BookingMailer.send_booking_approval_request_approved(
            uba.id
          ).deliver_later
        else
          Rails.logger.error(
            "Failed to save UserBookingApproval: #{uba.errors.full_messages.join(", ")}"
          )
        end
      end

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice: "All access requests approved successfully."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                alert:
                  "Failed to approve: #{e.record.errors.full_messages.join(", ")}"
  end

  def users
    render json: User.all
  end

  def bookings
    current_user
    @bookings = []
    if params[:room].present?
      SubSpaceBooking
        .where(sub_space_id: params[:room])
        .joins(:user)
        .find_each do |booking|
          booking_status =
            SubSpaceBookingStatus.find(booking.sub_space_booking_status_id)
          unless booking_status.booking_status_id ==
                   BookingStatus::APPROVED.id ||
                   booking_status.booking_status_id == BookingStatus::PENDING.id
            next
          end
          title = "#{booking.name} - #{booking.description}"
          title =
            if @user.admin? || booking.user == @user || booking.public
              title
            else
              booking.public ? title : "Space Booked"
            end
          title =
            if booking_status.booking_status_id == BookingStatus::PENDING.id
              title + " (Pending)"
            else
              title
            end
          title += " - #{booking.user.name}" if @user.admin? &&
            booking.user != @user
          title = "Space Blocked" if booking.blocking && !booking.public && (!@user.admin? || booking.user != @user)
          event = {
            id: "booking_" + booking.id.to_s + "_" + booking.sub_space_id.to_s,
            title: title,
            start: booking.start_time,
            end: booking.end_time,
            color: booking.color(@user.id)
          }
          @bookings << event
        end
    end
    # TODO: Allow search by recurring id
    render json: @bookings
  end

  def create
    booking = SubSpaceBooking.new(sub_space_booking_params)
    unless booking.valid?
      render json: {
               errors: booking.errors.full_messages
             },
             status: :unprocessable_content
      return
    end
    if params[:sub_space_booking][:blocking] == true && !current_user.admin?
      flash[:alert] = "You do not have permission to block a space."
      redirect_to sub_space_booking_index_path
    end

    if params[:sub_space_booking][:recurring] == true
      unless params[:sub_space_booking][:recurring_end].present? &&
               params[:sub_space_booking][:recurring_frequency].present?
        render json: {
                 errors: "Invalid recurring parameters"
               },
               status: :unprocessable_content
        return
      end
      recurrence =
        (
          if params[:sub_space_booking][:recurring_frequency] == "weekly"
            7.days
          else
            1.month
          end
        )
      start_date = Date.parse(params[:sub_space_booking][:start_time])
      end_date = Date.parse(params[:sub_space_booking][:end_time])

      start_time_str = Time.parse(params[:sub_space_booking][:start_time])
      end_time_str = Time.parse(params[:sub_space_booking][:end_time])

      end_date_r = Date.parse(params[:sub_space_booking][:recurring_end])

      start_time =
        DateTime.new(
          start_date.year,
          start_date.month,
          start_date.day,
          start_time_str.hour,
          start_time_str.min
        )
      end_time =
        DateTime.new(
          end_date.year,
          end_date.month,
          end_date.day,
          end_time_str.hour,
          end_time_str.min
        )
      end_date_recurring =
        DateTime.new(
          end_date_r.year,
          end_date_r.month,
          end_date_r.day
        ).beginning_of_day

      # book first one
      recurring_booking = RecurringBooking.new
      book(params, recurring_booking)

      while start_time < end_date_recurring
        params[:sub_space_booking][:start_time] = (
          start_time + recurrence
        ).strftime("%Y-%m-%d %H:%M")
        params[:sub_space_booking][:end_time] = (
          end_time + recurrence
        ).strftime("%Y-%m-%d %H:%M")

        start_date = Date.parse(params[:sub_space_booking][:start_time])
        end_date = Date.parse(params[:sub_space_booking][:end_time])

        start_time =
          DateTime.new(
            start_date.year,
            start_date.month,
            start_date.day,
            start_time_str.hour,
            start_time_str.min
          )
        end_time =
          DateTime.new(
            end_date.year,
            end_date.month,
            end_date.day,
            end_time_str.hour,
            end_time_str.min
          )
        book(params, recurring_booking, false) # book rest of recurring, don't send email for those
      end
    else
      book(params) # book single
    end
  end

  def book(params, recurring_booking = nil, send_email = true)
    booking = SubSpaceBooking.new(sub_space_booking_params)
    booking.sub_space = SubSpace.find(params[:sub_space_booking][:sub_space_id])
    booking.user_id = current_user.id
    unless booking.save
      render json: {
              errors: booking.errors.full_messages
            },
            status: :unprocessable_content
      return
    end

    # NOTE: postgres stores these without a timezone
    # So we receive time with no timezone, replace the time offset with the default one
    # Then convert to utc when doing comparaisons
    # This may explode once daylight savings are over...
    start_datetime =
      DateTime.parse(params[:sub_space_booking][:start_time]).change(
        offset: DateTime.now.offset
      ) # Rewrite timezone
    end_datetime =
      DateTime.parse(params[:sub_space_booking][:end_time]).change(
        offset: DateTime.now.offset
      )

    if params[:sub_space_booking][:blocking] != "true" &&
        SubSpaceBooking
          .where(sub_space_id: params[:sub_space_booking][:sub_space_id])
          .where(blocking: true)
          .where.not(id: booking.id)
          .where(
            "(start_time, end_time) OVERLAPS (?,?)",
            start_datetime.utc + 1.minute, # OVERLAPS performs half-open intersection
            end_datetime.utc - 1.minute
          )
          .any?
      booking.destroy
      flash[:alert] = "This time slot is already booked."
      respond_to do |format|
        format.json do
          render json: {
                  errors: ["TimeSlot This time slot is already booked."]
                },
                status: :unprocessable_content
        end
        format.html do
          redirect_to sub_space_booking_index_path(
                        anchor: "booking-calendar-tab",
                        room: params[:sub_space_booking][:sub_space_id]
                      )
        end
      end
      return
    end

    # Check time violations
    duration = (booking.end_time - booking.start_time) / 1.hour
    if !SubSpace
        .find(params[:sub_space_booking][:sub_space_id])
        .maximum_booking_duration
        .nil? && !current_user.admin? && (duration > booking.sub_space.maximum_booking_duration)
        render json: {
                errors: [
                  "DurationHour You cannot book #{booking.sub_space.name} for more than #{booking.sub_space.maximum_booking_duration} hours."
                ]
              },
              status: :unprocessable_content
        booking.destroy
        return
      end

    if !SubSpace
        .find(params[:sub_space_booking][:sub_space_id])
        .maximum_booking_hours_per_week
        .nil? && !current_user.admin?
      user_bookings =
        SubSpaceBooking
          .where(sub_space_id: booking.sub_space.id)
          .where(user_id: current_user.id)
          .where("start_time >= ?", DateTime.now.beginning_of_week)
          .where("start_time <= ?", DateTime.now.end_of_week)
      total_duration = 0 - duration
      user_bookings.each do |booking|
        total_duration += booking.end_time - booking.start_time
      end
      total_duration /= 1.hour
      if total_duration > booking.sub_space.maximum_booking_hours_per_week
        render json: {
                errors: [
                  "DurationWeek You cannot book #{booking.sub_space.name} for more than #{booking.sub_space.maximum_booking_hours_per_week} hours per week."
                ]
              },
              status: :unprocessable_content
        booking.destroy
        return
      end
    end

    status =
      SubSpaceBookingStatus.new(
        sub_space_booking_id: booking.id,
        booking_status_id:
          (
            # Auto-approve bookings made by admins
            if current_user.admin?
              BookingStatus::APPROVED.id
            elsif SubSpace.find(
                params[:sub_space_booking][:sub_space_id]
              ).approval_required
              if SubSpace
                  .find(params[:sub_space_booking][:sub_space_id])
                  .max_automatic_approval_hour
                  .nil?
                BookingStatus::PENDING.id
              elsif duration <=
                    SubSpace.find(
                      params[:sub_space_booking][:sub_space_id]
                    ).max_automatic_approval_hour
                BookingStatus::APPROVED.id
              elsif duration >
                    SubSpace.find(
                      params[:sub_space_booking][:sub_space_id]
                    ).max_automatic_approval_hour
                BookingStatus::PENDING.id
              end
            else
              BookingStatus::APPROVED.id
            end
          )
      )
    status.save
    booking.sub_space_booking_status_id = status.id
    booking.public =
      SubSpace.find(params[:sub_space_booking][:sub_space_id]).default_public
    booking.recurring_booking = recurring_booking # Attach the RecurringBooking handle, is saved with the booking itself
    
    # Set approved_at and approved_by for admin bookings
    if current_user.admin? && status.booking_status_id == BookingStatus::APPROVED.id
      booking.approved_at = DateTime.now
      booking.approved_by_id = current_user.id
    end
    
    booking.save
    flash[
      :notice
    ] = "Booking for #{booking.sub_space.name} created successfully."
    return unless send_email
      if booking.sub_space_booking_status.booking_status_id == BookingStatus::PENDING.id
        BookingMailer.send_booking_needs_approval(booking.id).deliver_now
      elsif booking.sub_space_booking_status.booking_status_id == BookingStatus::APPROVED.id
        # Send appropriate confirmation for approved bookings
        if current_user.admin?
          BookingMailer.send_booking_approved(booking.id).deliver_now
        else
          BookingMailer.send_booking_automatically_approved(booking.id).deliver_now
          BookingMailer.send_booking_approved(booking.id).deliver_now
        end
      end
  end

  def edit
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    ssb_status = @sub_space_booking.sub_space_booking_status.booking_status_id

    if (
         ssb_status == BookingStatus::PENDING.id && !@user.admin? &&
           !@user.eql?(@sub_space_booking.user)
       ) || (ssb_status == BookingStatus::APPROVED.id && !@user.admin?)
      redirect_to sub_space_booking_index_path,
                  alert: "You can't access this subspace booking."
    end
  end

  def update
    @sub_space_booking = SubSpaceBooking.find(params[:sub_space_booking_id])

    unless @user.admin? ||
             @sub_space_booking.sub_space_booking_status.booking_status_id !=
               BookingStatus::APPROVED.id
      redirect_to sub_space_booking_index_path(
                    anchor: "booking-calendar-tab",
                    room: @sub_space_booking.sub_space_id
                  ),
                  alert: "You do not have permission to edit this booking"
      return
    end

    start_datetime =
      DateTime.parse(params[:sub_space_booking][:start_time]).change(
        offset: DateTime.now.offset
      ) # Rewrite timezone
    end_datetime =
      DateTime.parse(params[:sub_space_booking][:end_time]).change(
        offset: DateTime.now.offset
      )

    if SubSpaceBooking
         .where(sub_space_id: @sub_space_booking.sub_space.id)
         .where(blocking: true)
         .where.not(id: @sub_space_booking.id)
         .where(
           "(start_time, end_time) OVERLAPS (?,?)",
           start_datetime.utc + 1.minute,
           end_datetime.utc - 1.minute
         )
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

    if @sub_space_booking.update(sub_space_booking_params)
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
      render "edit"
    end
  end

  def approve
    booking =
      SubSpaceBookingStatus.find(
        SubSpaceBooking.find(
          params[:sub_space_booking_id]
        ).sub_space_booking_status_id
      )
    booking.booking_status_id = BookingStatus::APPROVED.id
    booking.save
    SubSpaceBooking.find(params[:sub_space_booking_id]).update(
      approved_at: DateTime.now,
      approved_by_id: current_user.id
    )

    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice:
                  "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} approved successfully."
    BookingMailer.send_booking_approved(
      params[:sub_space_booking_id]
    ).deliver_now
  end

  def decline
    booking =
      SubSpaceBookingStatus.find(
        SubSpaceBooking.find(
          params[:sub_space_booking_id]
        ).sub_space_booking_status_id
      )
    booking.booking_status_id = BookingStatus::DECLINED.id
    booking.save
    redirect_to sub_space_booking_index_path(anchor: "booking-admin-tab"),
                notice:
                  "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} declined successfully."
  end

  def bulk_approve_decline
    bulk_status = params[:bulk_status]
    booking_statuses =
      SubSpaceBookingStatus.joins(:sub_space_booking).where(
        sub_space_booking: {
          id: params[:sub_space_booking_ids]
        }
      )
    if bulk_status == "approve"
      booking_statuses.update_all(booking_status_id: BookingStatus::APPROVED.id)
      SubSpaceBooking.where(id: params[:sub_space_booking_ids]).update_all(
        approved_at: DateTime.now,
        approved_by_id: current_user.id
      )
      flash[:notice] = "Bookings approved"
    elsif bulk_status == "decline"
      booking_statuses.update_all(booking_status_id: BookingStatus::DECLINED.id)
      flash[:notice] = "Bookings declined"
    else
      flash[:alert] = "Failed to bulk update booking status"
    end
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
    destroy_booking(booking)
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
      remaining_bookings.each { |remaining| destroy_booking(remaining) }
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

  def load_recurring_bookings_for_page(paginated_bookings)
    # Get unique recurring_booking_ids from current page
    recurring_ids = paginated_bookings.map(&:recurring_booking_id).compact.uniq
    
    @recurring_bookings_map = {}
    
    return if recurring_ids.empty?
    
    # Load ALL pending bookings for these recurring groups (not just current page)
    # Use the same timestamp as the main query to avoid timing issues
    all_recurring_bookings = SubSpaceBooking
      .includes(:approved_by, :user, :sub_space_booking_status, sub_space: :space)
      .joins(:sub_space_booking_status)
      .where(recurring_booking_id: recurring_ids)
      .where(sub_space_booking_statuses: { booking_status_id: BookingStatus::PENDING.id })
      .where('sub_space_bookings.end_time > ?', @current_time)
      .order(start_time: :asc)
    
    # Group them by recurring_booking_id
    @recurring_bookings_map = all_recurring_bookings.group_by(&:recurring_booking_id)
  end

  def destroy_booking(booking)
    # FIXME: This is a one to one relation, so we have to unset
    # the relation before deleting to avoid foreign key issues.
    # Status should be a column in SubSpaceBooking, not in a separate table
    status = booking.sub_space_booking_status
    status.sub_space_booking_id = nil
    status.save
    booking.sub_space_booking_status_id = nil
    booking.save
    status.destroy!
    booking.destroy!
  end

  def current_bookings(booking_status_id)
    SubSpaceBookingStatus
      .includes(sub_space_booking: [:approved_by, :user, :recurring_booking, {sub_space: :space}])
      .where(booking_status_id: booking_status_id)
      .order("sub_space_bookings.start_time": :asc)
      .map { |booking_status| booking_status.sub_space_booking }
      .select { |booking| booking.end_time > @current_time }  # Use consistent timestamp
      .paginate(page: params[:pending_page], per_page: 15)
  end

  def old_bookings(booking_status_id)
    SubSpaceBookingStatus
      .includes(sub_space_booking: [:approved_by, :user, :recurring_booking, {sub_space: :space}])
      .where(booking_status_id: booking_status_id)
      .order("sub_space_bookings.start_time": :asc)
      .map { |booking_status| booking_status.sub_space_booking }
      .select { |booking| booking.end_time < @current_time }  # Use consistent timestamp
      .reverse
      .paginate(page: params[:old_approved_page], per_page: 15)
  end

  def user_account
    return unless current_user.nil?
      redirect_to login_path, alert: "You must be logged in to view this page."
    
  end
  def user_signed_in
    return if signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
      nil
    
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
end
