class SubSpaceBookingController < ApplicationController
  def index
    unless signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
      return
    end
    @subspace = SubSpace.find(params[:room]) if params[:room].present?
    @bookings = SubSpaceBooking.where(user_id: current_user.id)
  end

  def request_access
    if UserBookingApproval.where(user: current_user).first.nil?
      UserBookingApproval.create(
        user: current_user,
        date: Time.now,
        comments: params[:comments],
        approved: false
      )
      flash[:notice] = "Access request submitted successfully."
    else
      flash[:alert] = "You have already requested access."
    end
    redirect_to root_path
  end

  def approve_access
    if params[:id].nil?
      user = User.find(params[:user_id])
      UserBookingApproval.new(
        user: user,
        date: Time.now,
        approved: true,
        staff: current_user
      ).save
      user.update(booking_approval: true)
      user.save!
      redirect_to admin_sub_space_booking_index_path
    else
      user = UserBookingApproval.find(params[:id]).user
      UserBookingApproval.find(params[:id]).update(approved: true)
      UserBookingApproval.find(params[:id]).update(staff_id: current_user.id)
      user.booking_approval = true
      user.save!
      redirect_to admin_sub_space_booking_index_path,
                  notice: "Access request approved successfully."
    end
  end
  def deny_access
    user = UserBookingApproval.find(params[:id]).user
    UserBookingApproval.find(params[:id]).destroy
    user.booking_approval = false
    user.save!
    redirect_to admin_sub_space_booking_index_path,
                notice: "Access request denied successfully."
  end

  def users
    render json: User.all if current_user.admin? || current_user.staff?
  end
  def bookings
    @bookings = []
    if params[:room].present?
      SubSpaceBooking
        .where(sub_space_id: params[:room])
        .each do |booking|
          booking_status =
            SubSpaceBookingStatus.find(booking.sub_space_booking_status_id)
          if booking_status.booking_status_id == BookingStatus::APPROVED.id ||
               booking_status.booking_status_id == BookingStatus::PENDING.id
            color = booking.user == current_user ? "#49794b" : "#497979"
            if booking_status.booking_status_id == BookingStatus::PENDING.id
              color = booking.user == current_user ? "#B5A500" : "#FFA500"
            end
            title = "#{booking.name} - #{booking.description}"
            title =
              (
                current_user.admin? || booking.user == current_user ||
                  booking.public
              ) ?
                title :
                booking.public ? title : "Space Booked"
            title =
              (
                if booking_status.booking_status_id == BookingStatus::PENDING.id
                  title + " (Pending)"
                else
                  title
                end
              )
            title += " - #{booking.user.name}" if current_user.admin? &&
              booking.user != current_user
            event = {
              id:
                "booking_" + booking.id.to_s + "_" + booking.sub_space_id.to_s,
              title: title,
              start: booking.start_time,
              end: booking.end_time,
              color: color
            }
            @bookings << event
          end
        end
    end
    render json: @bookings
  end

  def create
    unless signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
      return
    end
    unless current_user.booking_approval || current_user.admin?
      redirect_to root_path, alert: "You must be approved to book spaces."
      return
    end

    if params[:sub_space_booking][:recurring].present?
      if params[:sub_space_booking][:recurring] == true
        if params[:sub_space_booking][:recurring_end].present? &&
             params[:sub_space_booking][:recurring_frequency].present?
          if params[:sub_space_booking][:recurring_frequency] == "weekly"
            start_time = params[:sub_space_booking][:start_time].to_datetime
            end_time = params[:sub_space_booking][:end_time].to_datetime
            end_date = params[:sub_space_booking][:recurring_end].to_date
            book(params)
            while start_time < end_date
              params[:sub_space_booking][:start_time] = start_time + 7.days
              params[:sub_space_booking][:end_time] = end_time + 7.days
              start_time = params[:sub_space_booking][:start_time].to_datetime
              end_time = params[:sub_space_booking][:end_time].to_datetime
              book(params)
            end
          elsif params[:sub_space_booking][:recurring_frequency] == "monthly"
            start_time = params[:sub_space_booking][:start_time].to_datetime
            end_time = params[:sub_space_booking][:end_time].to_datetime
            end_date = params[:sub_space_booking][:recurring_end].to_date
            book(params)
            while start_time < end_date
              params[:sub_space_booking][:start_time] = start_time + 1.month
              params[:sub_space_booking][:end_time] = end_time + 1.month
              start_time = params[:sub_space_booking][:start_time].to_datetime
              end_time = params[:sub_space_booking][:end_time].to_datetime
              book(params)
            end
          else
            redirect_to root_path, alert: "You must select a recurring type."
          end
        else
          redirect_to root_path,
                      alert: "You must provide a recurring end date and type."
          return
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
          .where("start_time >= ?", Date.today.beginning_of_week)
          .where("start_time <= ?", Date.today.end_of_week)
      total_duration = 0 - duration
      user_bookings.each do |booking|
        total_duration += booking.end_time - booking.start_time
      end
      total_duration = total_duration / 1.hour
      # Check if the total duration is within the maximum duration per week
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
              BookingStatus::PENDING.id
            else
              BookingStatus::APPROVED.id
            end
          )
      )
    status.save
    booking.sub_space_booking_status_id = status.id
    booking.save
    flash[
      :notice
    ] = "Booking for #{booking.sub_space.name} created successfully."
    if booking.sub_space.approval_required
      BookingMailer.send_booking_needs_approval(booking.id).deliver_now
    end
  end

  def admin
    unless current_user.admin? || current_user.staff?
      flash[:alert] = "You are not authorized to view this page."
      redirect_to root_path
    end
    @bookings =
      SubSpaceBooking.where("start_time >= ?", Date.today).sort_by(&:start_time)
    @old_bookings =
      SubSpaceBooking.where("start_time < ?", Date.today).sort_by(&:start_time)
  end

  def approve
    unless current_user.admin? || current_user.staff?
      redirect_to root_path, alert: "You are not authorized to view this page."
      return
    end

    booking =
      SubSpaceBookingStatus.find(
        SubSpaceBooking.find(
          params[:sub_space_booking_id]
        ).sub_space_booking_status_id
      )
    booking.booking_status_id = BookingStatus::APPROVED.id
    booking.save
    redirect_to admin_sub_space_booking_index_path,
                notice:
                  "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} approved successfully."
    BookingMailer.send_booking_approved(booking.id).deliver_now
  end

  def decline
    unless current_user.admin? || current_user.staff?
      return(
        redirect_to root_path,
                    alert: "You are not authorized to view this page."
      )
    end
    booking =
      SubSpaceBookingStatus.find(
        SubSpaceBooking.find(
          params[:sub_space_booking_id]
        ).sub_space_booking_status_id
      )
    booking.booking_status_id = BookingStatus::DECLINED.id
    booking.save
    redirect_to admin_sub_space_booking_index_path,
                notice:
                  "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} declined successfully."
  end

  def publish
    unless current_user.admin?
      return(
        redirect_to root_path,
                    alert: "You are not authorized to view this page."
      )
    end
    booking = SubSpaceBooking.find(params[:sub_space_booking_id])
    booking.public = !booking.public
    booking.save
    redirect_to admin_sub_space_booking_index_path,
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
    redirect_to sub_space_booking_index_path,
                notice: "Booking for #{subspaceName} deleted successfully."
  end

  def sub_space_booking_params
    params.require(:sub_space_booking).permit(
      :start_time,
      :end_time,
      :name,
      :description,
      :sub_space_id
    )
  end
end
