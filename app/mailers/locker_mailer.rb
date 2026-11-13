# frozen_string_literal: true

class LockerMailer < ApplicationMailer
  before_action do
    @locker_rental = params[:locker_rental]
    @user = @locker_rental.rented_by
  end

  def locker_requested
    if @locker_rental.requested_as_student?
      staff_mail('makerlab@uottawa.ca', 'subject_student')
    else
      staff_mail('ceed@uottawa.ca', 'subject')
    end
  end

  def locker_assigned
    renter_mail('subject', specifier: @locker_rental.locker.specifier)
  end

  def locker_checkout
    renter_mail('subject', specifier: @locker_rental.locker.specifier)
  end

  # Sent when a locker is cancelled or manually finished by staff
  def locker_cancelled
    # Sometimes requests are cancelled before they're assigned
    if @locker_rental.locker
      renter_mail('subject_with_locker', specifier: @locker_rental.locker.specifier)
    else
      renter_mail('subject_without_locker')
    end
  end

  # Sent automatically when the rental end date passes
  def rental_expired
    renter_mail('subject', specifier: @locker_rental.locker&.specifier)
  end

  def locker_moved
    @moved_locker = params[:moved_locker]
    @moved_date = params[:moved_date]
    renter_mail('subject', specifier: @locker_rental.locker&.specifier)
  end

  private

  # Every mail to the renter goes through here: a soft-deleted or deactivated account gets nothing (checked
  # when the job runs, so a mail queued before the deactivation is dropped too). Returning without calling
  # mail makes the delivery a no-op. The subject is written in the renter's saved language.
  def renter_mail(subject_key, **values)
    return unless @locker_rental.renter_eligible?(lock: false)

    mail(to: @user.email, subject: subject_for(@user.email, subject_key, **values))
  end

  # Mail to staff (locker_requested) is not the renter's.
  def staff_mail(address, subject_key)
    mail(to: address, subject: subject_for(address, subject_key))
  end

  def subject_for(address, subject_key, **values)
    I18n.t("locker_mailer.#{action_name}.#{subject_key}", locale: recipient_locale(address), **values)
  end
end
