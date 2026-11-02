# frozen_string_literal: true

# Staff decision on a held locker payment (one the webhook recorded but could not apply): the money was
# refunded in Shopify, or the payment is dismissed (with a note). A payment is never applied by hand: assigning
# the rental active settles ONE held payment (LockerRentalsController#update), so a duplicate stays visible. Cancelling the rental does not resolve it.
class LockerPaymentsController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :require_staff

  def update
    rental = LockerRental.find(params[:locker_rental_id])
    payment = rental.locker_payments.find(params[:id])

    # Under the rental lock, like the assignment that settles payments: resolving and settling are serialised.
    outcome = LockerRental.transaction do
      rental.lock!
      if LockerPayment::RESOLUTIONS.exclude?(params[:resolution].to_s)
        :invalid
      elsif payment.resolve!(params[:resolution], by: current_user, note: params[:resolution_note])
        :resolved
      else
        :already_resolved
      end
    end

    case outcome
    when :resolved then redirect_to rental, notice: t("lockers.held_payments.resolved_#{payment.status}")
    when :already_resolved then redirect_to rental, alert: t('lockers.held_payments.already_resolved')
    else redirect_to rental, alert: t('lockers.held_payments.invalid_resolution')
    end
  end

  private

  def require_staff
    head :forbidden unless current_user.staff?
  end
end
