class LockersController < AdminAreaController
  before_action :signed_in

  before_action do
    unless current_user.staff?
      flash[:alert] = "You cannot access this area"
      redirect_back(fallback_location: root_path)
    end
  end

  helper_method :rental_state_icon

  def index
    # For the locker rental form
    # This works on the basis that there's only one active locker rental
    @lockers = Locker.includes(locker_rentals: [:rented_by, :decided_by])
    @locker_product_link = LockerOption.locker_product_link
    @locker_product_info = LockerOption.locker_product_info
  end

  # Make a range of lockers
  # Maybe later this can be modified to take explicit non-numeric names
  def create
    if locker_params[:range_start] >= locker_params[:range_end]
      flash[:alert] = "Range end must be larger than range start"
      return
    end

    @lockers =
    Locker.create(
      (locker_params[:range_start].to_i..locker_params[:range_end].to_i)
                    .map{ |specifier| {specifier:} }
    )
    render action: :index, status: :created
  end

  def price
    # Updates db value
    LockerOption.locker_product_link = params.require(:value)
    redirect_to lockers_path
  end

  def enabled
    LockerOption.lockers_enabled = (params.require(:value) == 't')
    redirect_to lockers_path
  end

  private

  def locker_params
    params.permit(:range_start, :range_end)
  end

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
