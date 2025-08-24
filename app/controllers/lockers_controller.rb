class LockersController < StaffAreaController
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
    @lockers = Locker.all
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
