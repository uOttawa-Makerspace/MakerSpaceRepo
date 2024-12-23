# frozen_string_literal: true

class LockerRentalsController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
    @locker_types = LockerType.all
    @locker_rentals =
      LockerRental.includes(:locker_type, :rented_by).order(
        locker_type_id: :asc
      )
  end

  def new
    # fun fact this isn't used at all by the view
    # because all the fields are given default values
    # but we keep it in case something changes to avoid breakage
    @locker_request = LockerRental.new
    # Don't allow new request if user already has an active or pending request
  end

  def create
    @locker_rental = LockerRental.new(locker_rental_params)
    # if not a staff member or has debug value set
    if !current_user.staff? || params[:locker_request][:ask]
      # Wait for admin approval
      @locker_rental.state = :reviewing
    end
    if @locker_rental.save
      redirect_back fallback_location: lockers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @locker_rental = LockerRental.find(params[:id])
    if @locker_rental.update(locker_rental_params)
      flash[:notice] = "Locker rental updated"
    else
      flash[:alert] = "Failed to update locker rental"
    end
  end

  private

  def locker_rental_params
    if current_user.admin?
      admin_params =
        params.require(:locker_rental).permit(
          :locker_type_id,
          # admin can assign and approve requests
          :rented_by_id,
          :locker_specifier,
          :state,
          :owned_until
        )

      # FIXME replace that search with a different one, return ID instead
      # If username is given (since search can do that)
      rented_by_user =
        User.find_by(username: params.dig(:locker_rental, :rented_by_username))
      if rented_by_user
        # then convert to user id
        admin_params.reverse_merge!(rented_by_id: rented_by_user.id)
      end
      admin_params
    else
      # people pick where they want a locker
      params.require(:locker_rental).permit(:locker_type)
      #.merge({ state: :reviewing })
    end
  end
end
