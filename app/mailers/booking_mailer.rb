class BookingMailer < ApplicationMailer
  # Receives the mails meant for a space's managers when the space has none.
  MTC_MAILBOX = "mtc@uottawa.ca"

  def send_booking_needs_approval(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)

    return if @sub_space.approval_required == false
    @emails = manager_emails(@booking.sub_space.space)
    @message =
      "A booking has been made in " + @sub_space.name + " by " + booker_name +
        " for " + @booking.description + " on " +
        @booking.start_time.to_formatted_s(:long) + " to " +
        @booking.end_time.to_formatted_s(:long) +
        ". Please check the Booking Admin Panel to approve or decline this booking."
    mail(to: @emails, subject: "Booking needs approval")
  end

  def send_booking_automatically_approved(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)
    @emails = manager_emails(@booking.sub_space.space)
    @message =
      "A booking has been made and automatically approved in " +
        @sub_space.name + " by " + booker_name + " for " +
        @booking.description + " on " +
        @booking.start_time.to_formatted_s(:long) + " to " +
        @booking.end_time.to_formatted_s(:long) +
        ". If you want to disable automatic booking for this subspace, go to the admin space page."

    mail(to: @emails, subject: "Booking automatically approved.")
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

  def send_booking_approval_request_sent(booking_approval_id, emails)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user

    return if emails.empty? || @user.deleted?

    @message =
      "A user by the name of " + @user.name +
        " has requested to be a room booker in makeroom. Please go to the
                <a href='https://makerepo.com/sub_space_booking'>MakeRepo Booking</a> admin
                panel to approve or deny this request."
    mail(to: emails, subject: "Booking approval request sent")
  end

  def send_booking_approval_request_approved(booking_approval_id)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user
    @email = requester_email
    return if @email.nil?

    @message =
      "Your booking approval request has been reviewed and accepted by an admin. Please go to the
                <a href='https://makerepo.com/sub_space_booking'>MakeRepo Booking</a> page if you would like to book rooms."
    mail(to: @email, subject: "Booking approval request accepted")
  end

  # Tells the requester that their request was declined, or their access revoked, with the
  # reason when staff gave one. French first, then English, like the other mails sent to users.
  def send_booking_access_denied(booking_approval_id)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user
    email = requester_email
    return if email.nil?

    key = "booking_mailer.access_denied.subject.#{@user_booking_approval.status}"
    @subject = "MakerRepo - #{I18n.t(key, locale: :fr)} // #{I18n.t(key, locale: :en)}"
    mail(to: email, subject: @subject)
  end

  private

  # Where a mail to the requester goes: nil, so nothing is sent, when the account was deleted or
  # has no email.
  def requester_email
    @user.email.presence unless @user.deleted?
  end

  # The space managers' emails; the MTC mailbox, with the missing managers
  # reported, when the space has none.
  def manager_emails(space)
    emails = space.space_managers.map(&:email)
    return emails if emails.any?

    Rails.error.report(
      RuntimeError.new("Booking mail for space #{space.id} (#{space.name}), which has no space managers; sent to #{MTC_MAILBOX}"),
      handled: true,
      severity: :warning
    )
    [MTC_MAILBOX]
  end

  # The booker's name, marked when the account is deleted; the booking title when it has no user.
  def booker_name
    user = @booking.display_user
    return @booking.name if user.nil?

    user.deleted? ? I18n.t("users.deleted_account", name: user.name) : user.name
  end
end
