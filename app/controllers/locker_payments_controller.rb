# frozen_string_literal: true

# Staff decision on a held locker payment (one the webhook recorded but could not apply): the money was
# refunded in Shopify, the payment is dismissed, or (rental active, renter eligible again) it is applied.
# Assigning the rental active settles one of them instead (LockerRentalsController#update). Cancelling the rental does not resolve it.
class LockerPaymentsController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :require_staff

  def update
    rental = LockerRental.find(params[:locker_rental_id])
    payment = rental.locker_payments.find(params[:id])

    case params[:resolution].to_s
    when 'applied'
      # The rental must be active and its renter eligible again; checked under lock in LockerPayment#apply!
      if payment.apply!(by: current_user, note: params[:resolution_note])
        redirect_to rental, notice: t('lockers.held_payments.resolved_applied')
      else
        redirect_to rental, alert: t('lockers.held_payments.cannot_apply')
      end
    when *LockerPayment::RESOLUTIONS
      if payment.resolve!(params[:resolution], by: current_user, note: params[:resolution_note])
        redirect_to rental, notice: t("lockers.held_payments.resolved_#{payment.status}")
      else
        redirect_to rental, alert: t('lockers.held_payments.already_resolved')
      end
    else
      redirect_to rental, alert: t('lockers.held_payments.invalid_resolution')
    end
  end

  private

  def require_staff
    head :forbidden unless current_user.staff?
  end
end
