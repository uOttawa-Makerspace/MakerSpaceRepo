class LockerSizesController < AdminAreaController
  def create
    LockerSize.create(locker_size_params)
    redirect_to lockers_path
  end

  def update
    LockerSize.find(params[:id]).update(locker_size_params)
      redirect_to lockers_path
  end

  def delete
    LockerSize.find(params[:id]).destroy
    redirect_to lockers_path
  end

  private

  def locker_size_params
    params.require(:locker_size).permit(
      :size,
      :shopify_gid
    )
  end
end
