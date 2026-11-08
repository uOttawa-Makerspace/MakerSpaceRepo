class LockersController < AdminAreaController
  # Guests are sent to the login page before the admin check can send them away.
  prepend_before_action :signed_in
  before_action :locker_queries, only: %i[show create create_multiple update]

  helper_method :rental_state_icon

  def index
    # For the locker rental form
    # This works on the basis that there's only one active locker rental
    @lockers =
      Locker.includes(locker_rentals: %i[rented_by decided_by]).includes(
        :locker_size
      )

    # Link to makerstore object
    @locker_product_link = LockerOption.locker_product_link

    # Locker sizes stored in DB
    @locker_sizes = LockerSize.all
    # Locker sizes received from makerstore
    @locker_product_info = LockerOption.locker_product_info

    @local_lookup = @locker_sizes.index_by(&:shopify_gid)

    variants = (@locker_product_info.is_a?(Hash) && @locker_product_info[:variants]) || {}
    @makerstore_lookup = variants.transform_keys { |gid| gid }
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
      flash.now[:alert] = validation_message(@locker, "errors.lockers.locker_not_saved")
      render :index, status: :unprocessable_entity
    end
  end

  # Custom route to create a range of lockers at once
  def create_multiple
    if locker_range_create_params[:range_start] >= locker_range_create_params[:range_end]
      flash[:alert] = I18n.t('errors.lockers.range_invalid')
      redirect_to lockers_path(anchor: 'lockerInventory')
      return
    end

    @lockers =
      Locker.create(
        (
          locker_range_create_params[:range_start].to_i..locker_range_create_params[:range_end].to_i
        ).map do |specifier|
          {
            specifier: specifier,
            locker_size_id: locker_range_create_params[:locker_size_id]
          }
        end
      )
    unsaved = @lockers.reject(&:persisted?)
    if unsaved.empty?
      flash[:notice] = 'Lockers created'
    else
      flash[:alert] = I18n.t('errors.lockers.range_not_created', lockers: specifiers_of(unsaved))
    end
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
      message = validation_message(@locker, "errors.lockers.locker_not_saved")
      respond_to do |format|
        format.html do
          flash.now[:alert] = message
          render :show, status: :unprocessable_content
        end
        # the field errors as before, plus the sentence to show
        format.json { render json: @locker.errors.to_hash.merge(error: message), status: :unprocessable_content }
      end
    end
  end

  def destroy
    @locker = Locker.find(params[:id])
    if @locker.destroy
      flash[:notice] = 'Locker removed'
      redirect_to lockers_path
    else
      redirect_to @locker,
                  alert: "#{I18n.t('errors.lockers.locker_not_deleted', specifier: @locker.specifier)} " \
                         "#{@locker.errors.full_messages.to_sentence}"
    end
  end

  def bulk_edit
    # The Javascript on the frontend populates params[:id] with the selected locker IDs
    if params[:bulk_delete]
      bulk_delete_lockers
    else
      bulk_update_lockers
    end

    redirect_to lockers_path(anchor: 'lockerInventory')
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

  # Delete button: a locker with any rental history is refused, one by one, and reported; the others
  # are deleted.
  def bulk_delete_lockers
    refused = []
    Locker.where(id: params[:id]).find_each { |locker| refused << (locker.specifier.presence || "##{locker.id}") unless locker.destroy }
    if refused.empty?
      flash[:notice] = 'Selected lockers deleted'
    else
      flash[:alert] = I18n.t('errors.lockers.bulk_not_deleted', lockers: refused.sort_by(&:to_s).to_sentence)
    end
  end

  # Update button: the lockers the new values were refused for are named.
  def bulk_update_lockers
    failed = []
    Locker
      .where(id: params[:id])
      .includes(:locker_size)
      .find_each { |locker| failed << locker unless locker.update(locker_params) }

    if failed.empty?
      flash[:notice] = 'Lockers updated'
    else
      flash[:alert] = I18n.t('errors.lockers.bulk_not_updated', lockers: specifiers_of(failed))
    end
  end

  # "12, 15 and #7": each locker's stored specifier (a refused edit has already assigned the new one
  # in memory), the one it was asked to have if it was never stored, or its id when it has none.
  def specifiers_of(lockers)
    lockers.map { |locker| locker.specifier_in_database.presence || locker.specifier.presence || "##{locker.id}" }
           .sort_by(&:to_s).to_sentence
  end

  def locker_sizes_lineup
    makerstore_sizes = @locker_product_info
  end

  def locker_queries
    @locker_sizes = LockerSize.all
    @locker_product_link = LockerOption.locker_product_link
    @locker_product_info = LockerOption.locker_product_info || {}
  end

  def locker_range_create_params
    params.permit(:range_start, :range_end, :locker_size_id, :available)
  end

  def locker_params
    # Permit the new notes and audience fields for unassigned lockers
    params.require(:locker).permit(:locker_size_id, :specifier, :available, :notes, :audience)
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
