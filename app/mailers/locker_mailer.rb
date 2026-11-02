# frozen_string_literal: true

class LockerMailer < ApplicationMailer
  before_action do
    @locker_rental = params[:locker_rental]
    @user = @locker_rental.rented_by
  end

  def locker_requested
    if @locker_rental.requested_as_student?
      mail(
        to: 'makerlab@uottawa.ca',
        subject: 'New locker request for a GNG project'
      )
    else
      mail(to: 'ceed@uottawa.ca', subject: 'New locker request')
    end
  end

  def locker_assigned
    renter_mail(subject:
        "Locker #{@locker_rental.locker.specifier} has been assigned for you"
    )
  end

  def locker_checkout
    renter_mail(subject:
        "Your locker rental for locker #{@locker_rental.locker.specifier} is ready for checkout"
    )
  end

  # Sent when a locker is cancelled or manually finished by staff
  def locker_cancelled
    # Sometimes requests are cancelled before they're assigned
    renter_mail(subject:
        (
          if @locker_rental.locker
            "Your locker rental for locker #{@locker_rental.locker.specifier} has been cancelled"
          else
            'Your locker rental request has been cancelled'
          end
        )
    )
  end

  # Sent automatically when the rental end date passes
  def rental_expired
    renter_mail(subject: "Your locker rental for Locker #{@locker_rental.locker&.specifier} has expired - Please clear your locker"
    )
  end

  def locker_moved
    @moved_locker = params[:moved_locker]
    @moved_date = params[:moved_date]
    renter_mail(subject: "Your locker rental for Locker #{@locker_rental.locker&.specifier} has been modified"
      )
  end

  private

  # Every mail to the renter goes through here: a soft-deleted or deactivated account gets nothing (checked
  # when the job runs, so a mail queued before the deactivation is dropped too). Returning without calling
  # mail makes the delivery a no-op. Mail to staff (locker_requested) is not the renter's.
  def renter_mail(**headers)
    return unless @locker_rental.renter_eligible?(lock: false)

    mail(to: @user.email, **headers)
  end
end
