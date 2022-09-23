class SubSpaceBookingController < ApplicationController
  def index
  end

  def bookings
    bookings = []
    if params[:room].present?
      SubSpaceBooking
        .where(sub_space_id: SubSpace.where(name: params[:room]).first.id)
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
            bookings << event
          end
        end
    end
    render json: bookings
  end

  def create
    @booking = SubSpaceBooking.new(sub_space_booking_params)
    @booking.sub_space_id =
      SubSpace.where(name: params[:sub_space_booking][:room]).first.id
    @booking.user_id = current_user.id

    unless @booking.save
      render json: {
               errors: @booking.errors.full_messages
             },
             status: :unprocessable_entity
      return
    end
    status =
      SubSpaceBookingStatus.new(
        sub_space_booking_id: @booking.id,
        booking_status:
          (
            if SubSpace.find_by(
                 name: params[:sub_space_booking][:room]
               ).approval_required
              BookingStatus::PENDING
            else
              BookingStatus::APPROVED
            end
          )
      )
    status.save
    @booking.sub_space_booking_status_id = status.id
    @booking.save
    flash[
      :notice
    ] = "Booking for #{params[:sub_space_booking][:room]} created successfully."
  end

  def admin
    unless current_user.admin? || current_user.staff?
      flash[:alert] = "You are not authorized to view this page."
      redirect_to root_path
    end
    @bookings = SubSpaceBooking.all
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
      :description
    )
  end
end
