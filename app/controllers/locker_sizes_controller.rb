class LockerSizesController < AdminAreaController
  # Guests are sent to the login page before the admin check can send them away.
  prepend_before_action :signed_in

  def create
    size = LockerSize.new(locker_size_params)
    if size.save
      redirect_to lockers_path(anchor: 'productVariants')
    else
      redirect_to lockers_path(anchor: 'productVariants'), alert: size.errors.full_messages.to_sentence
    end
  end

  def update
    size = LockerSize.find(params[:id])
    if size.update(locker_size_params)
      redirect_to lockers_path
    else
      redirect_to lockers_path, alert: size.errors.full_messages.to_sentence
    end
  end

  def destroy
    size = LockerSize.find(params[:id])
    if size.destroy
      redirect_to lockers_path
    else
      redirect_to lockers_path, alert: size.errors.full_messages.to_sentence
    end
  end

  private

  def locker_size_params
    params.require(:locker_size).permit(
      :size,
      :shopify_gid
    )
  end
end
