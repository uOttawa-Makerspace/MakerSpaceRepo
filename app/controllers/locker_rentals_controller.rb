# frozen_string_literal: true

class LockerRentalsController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
    # Only admin can see index list
    redirect_to :new_locker_rental unless current_user.admin?

    @locker_types = LockerType.all
    @locker_rentals =
      LockerRental.includes(:locker_type, :rented_by).order(
        locker_type_id: :asc
      )
  end

  def new
    @locker_rental = LockerRental.new
    # Only locker types enabled by admin
    new_instance_attributes
  end

  def create
    @locker_rental = LockerRental.new(locker_rental_params)
    # if not admin member or has debug value set
    # then force to wait for admin approval
    if !current_user.admin? || params.dig(:locker_rental, :ask)
      @locker_rental.state = :reviewing
      @locker_rental.rented_by = current_user
    end

    if @locker_rental.save
      redirect_back fallback_location: :new_locker_rental
    else
      new_instance_attributes
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

  def new_instance_attributes
    @available_locker_types = LockerType.available
    # Who users can request as
    # because we want to localize later
    @available_fors = {
      staff: ("CEED staff member" if current_user.staff?),
      student: ("GNG student" if current_user.student?),
      general: "community member"
    }.compact.invert
    # Don't allow new request if user already has an active or pending request
    @pending_locker_request = current_user.locker_rentals.under_review.first
  end

  def locker_rental_params
    if current_user.admin? && !params.dig(:locker_rental, :ask)
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
      params.require(:locker_rental).permit(:locker_type_id)
      #.merge({ state: :reviewing })
    end
  end
end
