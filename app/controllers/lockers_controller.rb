class LockersController < ApplicationController
  before_action :current_user
  before_action :signed_in

  helper_method :rental_state_icon

  def index
    @locker_types = LockerType.all
    @all_locker_rentals = LockerRental.all
    @locker_request_reviewing = LockerRental.where(state: :reviewing)
    @locker_request_await_payment = LockerRental.where(state: :await_payment)
    @locker_request_active = LockerRental.where(state: :active)

    # For the locker type form
    @locker_type = LockerType.new
    # For the locker rental form
    @locker_rental = LockerRental.new
  end

  def new
  end

  def create
  end

  def types
  end

  private

  def rental_state_icon(state)
    case state
    when "active"
      "fa-lock"
    when "cancelled"
      "fa-clock-o text-danger"
    else
      ""
    end
  end
end
