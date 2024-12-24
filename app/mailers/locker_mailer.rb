# frozen_string_literal: true
#
class LockerMailer < ApplicationMailer
  layout "msr_mailer"

  before_action do
    @locker_rental = params[:locker_rental]
    @user = params[:user]
  end

  def locker_assigned
    mail(
      to: @user.email,
      subject: "Locker #{@locker_rental.full_locker_name} assigned"
    )
  end
end
