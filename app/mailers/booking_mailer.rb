class BookingMailer < ApplicationMailer
  helper_method :booker_name

  # Receives the mails meant for a space's managers when the space has none.
  MTC_MAILBOX = "mtc@uottawa.ca"

  # The mails to staff, and the approval mails to a booker or applicant, are written in the recipient's saved language
  # (see ApplicationMailer#mail): a mail to several managers at once, or to the MTC mailbox, is in the site's default
  # language. Subjects come
  # from booking_mailer.<action>.subject.
  def send_booking_needs_approval(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)

    return if @sub_space.approval_required == false

    mail(to: manager_emails(@sub_space.space))
  end

  def send_booking_automatically_approved(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)
    mail(to: manager_emails(@sub_space.space))
  end

  def send_booking_approved(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = SubSpace.find(@booking.sub_space_id)
    @email = @booking.user.email

    return if @email.blank?

    mail(to: @email)
  end

  # Tells the booker that staff declined the booking. French first, then English, like the access mails.
  def send_booking_declined(booking_id)
    @booking = SubSpaceBooking.find(booking_id)
    @sub_space = @booking.sub_space
    @email = @booking.user&.email

    return if @email.blank?

    key = "booking_mailer.declined.subject"
    @subject = "MakerRepo - #{I18n.t(key, locale: :fr)} // #{I18n.t(key, locale: :en)}"
    mail(to: @email, subject: @subject)
  end

  def send_booking_approval_request_sent(booking_approval_id, emails)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user

    return if emails.empty? || @user.deleted?

    mail(to: emails)
  end

  def send_booking_approval_request_approved(booking_approval_id)
    @user_booking_approval = UserBookingApproval.find(booking_approval_id)
    @user = @user_booking_approval.user
    @email = requester_email
    return if @email.nil?

    mail(to: @email)
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
