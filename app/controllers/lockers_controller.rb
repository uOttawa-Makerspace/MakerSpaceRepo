class LockersController < ApplicationController
  before_action :current_user
  before_action :signed_in

  before_action do
    unless current_user.admin?
      flash[:alert] = "You cannot access this area"
      redirect_back(fallback_location: root_path)
    end
  end

  helper_method :rental_state_icon

  def index
    @locker_types = LockerType.all
    @locker_requests_pending = LockerRental.under_review.take 5

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
