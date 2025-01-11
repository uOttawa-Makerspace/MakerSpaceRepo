# frozen_string_literal: true

class LockerRentalsController < ApplicationController
  before_action :current_user
  before_action :signed_in, except: %i[stripe_success stripe_cancelled]
  # Also sets @locker_rental
  before_action :check_permission,
                except: %i[
                  index
                  new
                  create
                  update
                  stripe_success
                  stripe_cancelled
                ]

  def index
    # Only admin can see index list
    #redirect_to :new_locker_rental unless current_user.admin?

    @own_locker_rentals = current_user.locker_rentals
    if current_user.admin?
      @locker_types = LockerType.all
      @locker_rentals =
        LockerRental.includes(:locker_type, :rented_by).order(
          locker_type_id: :asc
        )
    end
  end

  def show
    if @locker_rental.await_payment?
      @stripe_checkout_session =
        Stripe::Checkout::Session.create(
          success_url: stripe_success_locker_rentals_url,
          cancel_url: stripe_cancelled_locker_rentals_url,
          mode: "payment",
          line_items: @locker_rental.locker_type.generate_line_items,
          billing_address_collection: "required",
          client_reference_id: "locker-rental-#{@locker_rental.id}"
        )
    end
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
    elsif current_user.admin? && locker_rental_params[:state] == "active"
      # if acting as admin
      # save down later
      @locker_rental.auto_assign
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

    # NOTE move this line to model maybe?
    # if changing state to 'active'
    if locker_rental_params[:state] == "active"
      # default to end of semester
      @locker_rental.owned_until ||= end_of_this_semester
      # Get first available locker specifier if not set
      @locker_rental.locker_specifier ||=
        @locker_rental.locker_type.get_available_lockers.first
    end

    if @locker_rental.update(locker_rental_params)
      flash[:notice] = "Locker rental updated"
    else
      flash[:alert] = "Failed to update locker rental" + helpers.tag.br +
        @locker_rental.errors.full_messages.join(helpers.tag.br)
    end

    redirect_back fallback_location: :locker_rentals
  end

  def stripe_success
  end

  def stripe_cancelled
  end

  private

  def check_permission
    # If user gives a request id
    if params[:id].present?
      @locker_rental = LockerRental.find(params[:id])
      # Allow if getting own locker rental
      return if @locker_rental.rented_by == current_user
    end
    # Always allow admin
    return if current_user.admin?

    # Else redirect to only page with no auth (new page takes no ID)
    redirect_to :new_locker_rental
  end

  def new_instance_attributes
    @available_locker_types = LockerType.available
    # Who users can request as
    # because we want to localize later
    # FIXME this is not used for anything, pretty useless
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
          :owned_until,
          :notes
        )
      # FIXME replace that search with a different one, return ID instead
      # If username is given (since search can do that)
      rented_by_user =
        User.find_by(username: params.dig(:locker_rental, :rented_by_username))
      if rented_by_user
        # then convert to user id
        admin_params.reverse_merge!(rented_by_id: rented_by_user.id)
      end
      return admin_params
    else
      # people pick where they want a locker
      # prevent user from editing rental notes after first submit
      params
        .require(:locker_rental)
        .permit(:locker_type_id)
        .tap { |p| p.permit(:notes) unless params[:id] }
    end
  end
end
