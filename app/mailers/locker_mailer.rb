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
      subject: "Locker #{@locker_rental.full_locker_name} assigned"
    )
  end

  def locker_checkout
    mail(
      to: @user.email,
      subject:
        "Your locker rental for #{@locker_rental.locker_type.short_form} is ready for checkout"
    )
  end

  def locker_cancelled
    mail(
      to: @user.email,
      subject:
        "Your locker rental for #{@locker_rental.locker_type.short_form} has been cancelled"
    )
  end
end
