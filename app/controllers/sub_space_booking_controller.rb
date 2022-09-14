class SubSpaceBookingController < ApplicationController
  def index
  end

  def create
  end

  def bookings
    bookings = []
    if params[:room].present?
      SubSpaceBooking
        .where(sub_space_id: SubSpace.where(name: params[:room]).first.id)
        .each do |booking|
          if booking.sub_space_booking_status.booking_status_id ==
               BookingStatus::APPROVED.id ||
               (
                 booking.sub_space_booking_status.booking_status_id ==
                   BookingStatus::PENDING.id &&
                   booking.user_id == current_user.id
               )
            color = "#497979"
            title = "Space Book"
            if booking.sub_space_booking_status.booking_status_id ==
                 BookingStatus::PENDING.id && booking.user_id == current_user.id
              color = "#FFA500"
              title = "Pending Approval"
            end
            event = {
              id:
                "booking_" + booking.id.to_s + "_" + booking.sub_space_id.to_s,
              title: title,
              start: booking.start,
              end: booking.end,
              color: color
            }
            bookings << event
          end
        end
    end
    render json: bookings
  end

  def book
    @booking = SubSpaceBooking.new(sub_space_booking_params)
    @booking.sub_space_id = SubSpace.where(name: params[:room]).first.id
    @booking.user_id = current_user.id
    if @booking.save
      flash[:notice] = "Booking for #{params[:room]} created successfully."
    else
      flash[:alert] = "Booking for #{params[:room]} failed to create."
    end
    status =
      SubSpaceBookingStatus.new(
        sub_space_booking_id: @booking.id,
        booking_status: BookingStatus::PENDING
      )
    status.save
    @booking.sub_space_booking_status_id = status.id
    @booking.save
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
      flash[:alert] = "You are not authorized to view this page."
      redirect_to root_path
    end
    booking = SubSpaceBookingStatus.find(params[:sub_space_booking_id])
    booking.booking_status_id = BookingStatus::APPROVED.id
    booking.save
    flash[
      :notice
    ] = "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} approved successfully."
    redirect_to admin_sub_space_booking_index_path
  end

  def decline
    unless current_user.admin? || current_user.staff?
      flash[:alert] = "You are not authorized to view this page."
      redirect_to root_path
    end
    booking = SubSpaceBookingStatus.find(params[:sub_space_booking_id])
    booking.booking_status_id = BookingStatus::DECLINED.id
    booking.save
    flash[
      :notice
    ] = "Booking for #{SubSpaceBooking.find(params[:sub_space_booking_id]).sub_space.name} declined successfully."
    redirect_to admin_sub_space_booking_index_path
  end

  def sub_space_booking_params
    params.require(:sub_space_booking).permit(:start, :end, :name, :description)
  end
end
