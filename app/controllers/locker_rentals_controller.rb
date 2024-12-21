# frozen_string_literal: true

class LockerRentalsController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def new
    @locker_rental = LockerRental.new
    @locker_types =
      LockerType.select(:short_form, :id).distinct.pluck(:short_form, :id)
    @assigned_lockers =
      LockerRental
        .all
        .select(:locker_specifier, :locker_type_id)
        .group_by(&:locker_type_id)
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

    @end_of_this_semester = end_of_this_semester.to_date
    # If user already has an active or pending request
    # don't allow new request
  end

  def create
    # TODO missing state, owned by
    # also the damn user search returns the username not the id, wtf???
    @locker_rental = LockerRental.new(locker_rental_params)
    if @locker_rental.valid?
      head :ok
    else
      head :unprocessable_entity
    end
  end

  private

  def end_of_this_semester
    if DateTime.now.month in 9..12
      # End of Fall
      DateTime.new(DateTime.now.year, 12).end_of_month
    elsif DateTime.now.month in 1..4
      # End of Winter
      DateTime.new(DateTime.now.year, 4).end_of_month
    elsif DateTime.now.month in 5..8
      # End of Summer
      DateTime.new(DateTime.now.year, 8).end_of_month
    end
  end

  def locker_rental_params
    if current_user.admin?
      params.require(:locker_rental).permit(
        :locker_type_id,
        # admin can assign and approve requests
        :rented_by_id,
        :locker_specifier,
        :state,
        :owned_until
      )
    else
      # people pick where they want a locker
      params
        .require(:locker_rental)
        .permit(:locker_type)
        .merge({ state: :reviewing })
    end
  end
end
