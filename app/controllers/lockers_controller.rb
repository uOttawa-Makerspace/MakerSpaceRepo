class LockersController < AdminAreaController
  before_action :signed_in
  before_action :locker_queries, only: %i[show create create_multiple update]

  before_action do
    unless current_user.staff?
      flash[:alert] = 'You cannot access this area'
      redirect_back(fallback_location: root_path)
    end
  end

  helper_method :rental_state_icon

  def index
    # For the locker rental form
    # This works on the basis that there's only one active locker rental
    @lockers =
      Locker.includes(locker_rentals: %i[rented_by decided_by]).includes(
        :locker_size
      )
    @locker_sizes = LockerSize.all
    @locker_product_link = LockerOption.locker_product_link
    @locker_product_info = LockerOption.locker_product_info
  end

  def show
    @locker = Locker.find(params[:id])
    @active_locker_rental = @locker.locker_rentals.active.first
  end

  # Make a range of lockers
  # Maybe later this can be modified to take explicit non-numeric names
  def create
    @locker = Locker.new(locker_params)

    if @locker.save
      flash[:notice] = "Created locker ##{@locker.specifier}"
      redirect_to @locker
    else
      flash[:alert] = @locker.errors.full_messages.to_sentence.to_s
      render :index, status: :unprocessable_entity
    end
  end

  # Custom route to create a range
  def create_multiple
    if locker_range_create_params[:range_start] >=
         locker_range_create_params[:range_end]
      flash[:alert] = 'Range end must be larger than range start'
      return
    end

    @lockers =
      Locker.create(
        (
          locker_range_create_params[
            :range_start
          ].to_i..locker_range_create_params[:range_end].to_i
        ).map do |specifier| # Map params to a create hash
          {
            specifier:,
            locker_size_id: locker_range_create_params[:locker_size_id]
          }
        end
      )
    flash[:notice] = 'Lockers created'
    redirect_to lockers_path(anchor: 'lockerInventory')
  end

  def update
    @locker = Locker.find(params[:id])
    if @locker.update(locker_params)
      respond_to do |format|
        format.html do
          flash[:notice] = 'Locker updated successfully'
          redirect_to @locker
        end
        format.json { head :no_content }
      end
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @locker = Locker.find(params[:id])
    if @locker.destroy
      flash[:notice] = 'Locker removed'
      redirect_to lockers_path
    else
      redirect_to @locker, alert: @discount.errors.full_messages.to_sentence
    end
  end

  def bulk_edit
    Locker
      .where(id: params[:id])
      .find_each { |locker| locker.update(locker_params) }

    redirect_to lockers_path
  end

  def price
    # Updates db value
    LockerOption.locker_product_link =
      "gid://shopify/Product/#{params.require(:value)}"
    redirect_to lockers_path
  end

  def enabled
    LockerOption.lockers_enabled = (params.require(:value) == 't')
    redirect_to lockers_path
  end

  private

  def locker_queries
    @locker_sizes = LockerSize.all
    @locker_product_link = LockerOption.locker_product_link
    @locker_product_info = LockerOption.locker_product_info
  end

  def locker_range_create_params
    params.permit(:range_start, :range_end, :locker_size_id, :available)
  end

  def locker_params
    params.require(:locker).permit(:locker_size_id, :specifier, :available)
  end

  def rental_state_icon(state)
    case state
    when 'active'
      'fa-lock'
    when 'cancelled'
      'fa-clock-o text-danger'
    else
      ''
    end
  end
end
