class LockersController < ApplicationController
  def index
    @locker_types = LockerType.all
    @locker_request_reviewing = LockerRental.where(state: :reviewing)
    @locker_request_await_payment = LockerRental.where(state: :await_payment)
    @locker_request_active = LockerRental.where(state: :active)
  end

  def new
  end

  def create
  end

  def types
  end
end
