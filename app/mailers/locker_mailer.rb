# frozen_string_literal: true
#
class LockerMailer < ApplicationMailer
  layout "msr_mailer"

  before_action do
    @locker_rental = params[:locker_rental]
    @user = @locker_rental.rented_by
  end

  def locker_assigned
    mail(
      to: @user.email,
      subject:
        "Locker #{@locker_rental.locker.specifier} has been assigned for you"
    )
  end

  def locker_checkout
    mail(
      to: @user.email,
      subject:
        "Your locker rental for locker #{@locker_rental.locker.specifier} is ready for checkout"
    )
  end

  def locker_cancelled
    # Sometimes requests are cancelled before they're assigned
    mail(
      to: @user.email,
      subject:
        (
          if @locker_rental.locker
            "Your locker rental for locker #{@locker_rental.locker.specifier} has been cancelled"
          else
            "Your locker rental request has been cancelled"
          end
        )
    )
  end
end
