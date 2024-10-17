class SubSpaceBookingController < ApplicationController
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
      if @subspace.default_public
        @rules << "bookings (Name and Description of event) are public by default"
      end
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
      # Need to get the booking status from the sub space booking status table for the booking
      @pending_bookings = current_bookings(BookingStatus::PENDING.id)
      @approved_bookings = current_bookings(BookingStatus::APPROVED.id)
      @declined_bookings = current_bookings(BookingStatus::DECLINED.id)
      @old_pending_bookings = old_bookings(BookingStatus::PENDING.id)
      @old_approved_bookings = old_bookings(BookingStatus::APPROVED.id)
      @old_declined_bookings = old_bookings(BookingStatus::DECLINED.id)
    end

    @supervisors = []
    SpaceManagerJoin.all.each do |smj|
      unless @supervisors.include?([smj.user.name, smj.user.id])
        @supervisors << [smj.user.name, smj.user.id]
      end
    end
    @supervisors = @supervisors.sort_by { |elem| elem[0].downcase }
  end

  def request_access
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
        flash[
          :alert
        ] = "Something went wrong when trying to request MakeRoom access. Please try again later."
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
          if booking.blocking
            title = "Space Blocked" if (
              !booking.public && ((!@user.admin?) || booking.user != @user)
            )
          end
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
    render json: @bookings
  end

  def create
    booking = SubSpaceBooking.new(sub_space_booking_params)
    unless booking.valid?
      render json: {
               errors: booking.errors.full_messages
             },
             status: :unprocessable_entity
      return
    end
    if params[:sub_space_booking][:blocking] && !current_user.admin?
      flash[:alert] = "You do not have permission to block a space."
      redirect_to sub_space_booking_index_path
    end
    if params[:sub_space_booking][:recurring].present?
      if params[:sub_space_booking][:recurring] == true
        if params[:sub_space_booking][:recurring_end].present? &&
             params[:sub_space_booking][:recurring_frequency].present?
          params[:sub_space_booking][:recurring_frequency] == "weekly" ?
            recurrence = 7.days :
            recurrence = 1.month
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

          book(params)

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
            book(params)
          end
        end
      end
    else
      book(params)
    end
  end

  def book(params)
    booking = SubSpaceBooking.new(sub_space_booking_params)
    booking.sub_space = SubSpace.find(params[:sub_space_booking][:sub_space_id])
    booking.user_id = current_user.id
    unless booking.save
      render json: {
               errors: booking.errors.full_messages
             },
             status: :unprocessable_entity
      return
    end

    # NOTE postgres stores these without a timezone
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
                 status: :unprocessable_entity
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
         .nil? && !current_user.admin?
      if duration > booking.sub_space.maximum_booking_duration
        render json: {
                 errors: [
                   "DurationHour You cannot book #{booking.sub_space.name} for more than #{booking.sub_space.maximum_booking_duration} hours."
                 ]
               },
               status: :unprocessable_entity
        booking.destroy
        return
      end
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
      total_duration = total_duration / 1.hour
      if total_duration > booking.sub_space.maximum_booking_hours_per_week
        render json: {
                 errors: [
                   "DurationWeek You cannot book #{booking.sub_space.name} for more than #{booking.sub_space.maximum_booking_hours_per_week} hours per week."
                 ]
               },
               status: :unprocessable_entity
        booking.destroy
        return
      end
    end

    status =
      SubSpaceBookingStatus.new(
        sub_space_booking_id: booking.id,
        booking_status_id:
          (
            if SubSpace.find(
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
    booking.save
    flash[
      :notice
    ] = "Booking for #{booking.sub_space.name} created successfully."
    if booking.sub_space.approval_required &&
         booking.sub_space_booking_status.booking_status_id ==
           BookingStatus::PENDING.id
      BookingMailer.send_booking_needs_approval(booking.id).deliver_now
    elsif !booking.sub_space.approval_required &&
          booking.sub_space_booking_status.booking_status_id ==
            BookingStatus::APPROVED.id
      BookingMailer.send_booking_automatically_approved(booking.id).deliver_now
      BookingMailer.send_booking_approved(booking.id).deliver_now
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
                 status: :unprocessable_entity
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
    status = SubSpaceBookingStatus.find(booking.sub_space_booking_status_id)
    status.sub_space_booking_id = nil
    status.save
    booking.sub_space_booking_status_id = nil
    booking.save
    status.destroy
    booking.destroy
    redirect_to sub_space_booking_index_path(anchor: "booking-tab"),
                notice: "Booking for #{subspaceName} deleted successfully."
  end

  def get_sub_space_booking
    sub_space_booking = SubSpaceBooking.find(params[:id])
    render json: { **sub_space_booking.as_json }
  end

  private

  def current_bookings(booking_status_id)
    SubSpaceBookingStatus
      .includes(sub_space_booking: [:approved_by, :user, sub_space: :space])
      .where(booking_status_id: booking_status_id)
      .order("sub_space_bookings.start_time": :asc)
      .map { |booking_status| booking_status.sub_space_booking }
      .select { |booking| booking.end_time > Time.now }
      #.sort_by { |booking| booking.start_time }
      .paginate(page: params[:pending_page], per_page: 15)
  end

  def old_bookings(booking_status_id)
    SubSpaceBookingStatus
      .includes(sub_space_booking: [:approved_by, :user, sub_space: :space])
      .where(booking_status_id: booking_status_id)
      .order("sub_space_bookings.start_time": :asc)
      .map { |booking_status| booking_status.sub_space_booking }
      .select { |booking| booking.end_time < Time.now }
      #.sort_by { |booking| booking.start_time }
      .reverse
      .paginate(page: params[:old_approved_page], per_page: 15)
  end

  def user_account
    unless !current_user.nil?
      redirect_to login_path, alert: "You must be logged in to view this page."
    end
  end
  def user_signed_in
    unless signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
      return
    end
  end
  def user_approved
    unless current_user.booking_approval || current_user.admin?
      redirect_to root_path,
                  alert: "You must be approved to book to view this page."
    end
  end
  def user_admin_or_staff
    unless current_user.admin? || current_user.staff?
      redirect_to root_path,
                  alert: "You must be an admin or staff to view this page."
    end
  end
  def user_admin
    unless current_user.admin?
      redirect_to root_path, alert: "You must be an admin to view this page."
    end
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
