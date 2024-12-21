class LockersController < ApplicationController
  def index
    @locker_types = LockerType.all
    @all_locker_rentals = LockerRental.all
    @locker_request_reviewing = LockerRental.where(state: :reviewing)
    @locker_request_await_payment = LockerRental.where(state: :await_payment)
    @locker_request_active = LockerRental.where(state: :active)

    # For the locker rental form
    @locker_type = LockerType.new
  end

  def new
  end

  def create
  end

  def types
  end
end
