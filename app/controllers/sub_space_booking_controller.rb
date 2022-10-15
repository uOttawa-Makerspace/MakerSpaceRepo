class SubSpaceBookingController < ApplicationController
  def index
    unless signed_in?
      redirect_to login_path, alert: "You must be logged in to view this page."
      return
    end
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
          if booking.sub_space_booking_status.booking_status ==
               BookingStatus::APPROVED ||
               booking.sub_space_booking_status.booking_status ==
                 BookingStatus::PENDING
            color = "#497979"
            title = "Space Booked"
            if booking.sub_space_booking_status.booking_status ==
                 BookingStatus::PENDING
              color = "#FFA500"
              title = "Pending Approval"
            end
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
    booking = SubSpaceBooking.new(sub_space_booking_params)
    booking.sub_space = SubSpace.find(params[:sub_space_booking][:sub_space_id])
    booking.user_id = current_user.id

    #ensure 4 basic validations are met
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
      total_duration = 0
      user_bookings.each do |booking|
        total_duration += booking.end_time - booking.start_time
      end
      total_duration += duration
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
        booking_status:
          (
            if SubSpace.find(
                 params[:sub_space_booking][:sub_space_id]
               ).approval_required
              BookingStatus::PENDINGsub_space_id
            else
              BookingStatus::APPROVED
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

    booking = SubSpaceBookingStatus.find(params[:sub_space_booking_id])
    booking.booking_status = BookingStatus::APPROVED
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
    booking = SubSpaceBookingStatus.find(params[:sub_space_booking_id])
    booking.booking_status = BookingStatus::DECLINED
    booking.save
    redirect_to admin_sub_space_booking_index_path,
                notice:
                  "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} declined successfully."
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
