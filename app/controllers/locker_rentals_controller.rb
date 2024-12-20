# frozen_string_literal: true

class LockerRentalsController < ApplicationController
  # TODO
  # before_action admin, except index

  def new
    @locker_rental = LockerRental.new
    @locker_types =
      LockerType.select(:short_form, :id).distinct.pluck(:short_form, :id)
    # this doesn't work BTW
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

    if current_user.admin?
      new_admin
      return
    end
    # If user already has an active or pending request
    # don't allow new request
  end

  def create
  end

  private

  def new_admin
  end

  def locker_rental_params
    if current_user.admin?
      params.require(:locker_rental).permit(
        :locker_type,
        # admin can assign and approve requests
        :rented_by,
        :locker_specifier,
        :state,
        :owned_until
      )
    else
      # people pick where they want a locker
      params.require(:locker_rental).permit(:locker_type)
    end
  end
end
