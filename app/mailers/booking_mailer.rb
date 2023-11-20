class BookingMailer < ApplicationMailer
  def send_booking_needs_approval(booking_id)
    @email =
      ContactInfo.find_by(
        space_id: SubSpaceBooking.where(id: booking_id).first.sub_space.space.id
      )&.email
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)

    return if @email.blank? || @sub_space.approval_required == false
    @message =
      "A booking has been made in " + @sub_space.name + " by " + @booking.name +
        " for " + @booking.description + " on " +
        @booking.start_time.to_formatted_s(:long) + " to " +
        @booking.end_time.to_formatted_s(:long) +
        ". Please check the Booking Admin Panel to approve or decline this booking."
    mail(to: @email, subject: "Booking needs approval")
  end

  def send_booking_automatically_approved(booking_id)
    @email =
      ContactInfo.find_by(
        space_id: SubSpaceBooking.where(id: booking_id).first.sub_space.space.id
      )&.email
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)

    return if @email.blank?
    @message =
      "A booking has been made and automatically approved in " +
        @sub_space.name + " by " + @booking.name + " for " +
        @booking.description + " on " +
        @booking.start_time.to_formatted_s(:long) + " to " +
        @booking.end_time.to_formatted_s(:long) +
        ". If you want to disable automatic booking for this subspace, go to the admin space page."

    mail(to: @email, subject: "Booking automatically approved.")
  end

  def send_booking_approved(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)
    @email = @booking.user.email

    return if @email.blank?
    @message =
      "Your booking in " + @sub_space.name + " for " + @booking.description +
        " on " + @booking.start_time.to_formatted_s(:long) + " to " +
        @booking.end_time.to_formatted_s(:long) + " has been approved."
    mail(to: @email, subject: "Booking approved")
  end

  def send_booking_approval_request_sent(booking_approval_id)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user
    @email = "" # TODO: add email for booking approval requests

    return if @email.blank?
    @message =
      "A user (" + @user.name +
        ") has requested to be a room booker in makeroom. Please go to the
                <a href='https://makerepo.com/sub_space_booking'>MakeRepo Booking</a> admin
                panel to approve or deny this request."
    mail(to: @email, subject: "Booking approval request sent")
  end

  def send_booking_approval_request_approved(booking_approval_id)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user
    @email = @user.email

    return if @email.blank?
    @message =
      "Your booking approval request has been reviewed and accepted by an admin. Please go to the
                <a href='https://makerepo.com/sub_space_booking'>MakeRepo Booking</a> page if you would like to book rooms."
    mail(to: @email, subject: "Booking approval request accepted")
  end
end
