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
    # TODO are these still being used? clean up
    @locker_rental = LockerRental.new
    @locker_types =
      LockerType.select(:short_form, :id).distinct.pluck(:short_form, :id)
    @assigned_lockers = LockerRental.get_assigned_lockers
    # We're faking lockers existing
    @available_lockers =
      LockerType.all.map do |type|
        [
          type.short_form,
          # 1. Make a list based of max quantity (so BRUNS-1, BRUNS-2, ..., BRUNS-99)
          ("1"..type.quantity.to_s) # 2. Subtract specifiers already assigned to active rentals
            .reject do |specifier|
            @assigned_lockers[type.id] &&
              @assigned_lockers[type.id].includes?(specifier)
          end
        ]
      end

    #@end_of_this_semester = end_of_this_semester.to_date
    # If user already has an active or pending request
    # don't allow new request
  end

  def create
    @locker_rental = LockerRental.new(locker_rental_params)
    if @locker_rental.save
      head :ok
    else
      head :unprocessable_entity
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
      params
        .require(:locker_rental)
        .permit(:locker_type)
        .merge({ state: :reviewing })
    end
  end
end
