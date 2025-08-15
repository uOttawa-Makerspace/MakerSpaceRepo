class LockerTypesController < StaffAreaController
  def index
    @locker_types = LockerType.all
    # For the locker type form
    @locker_type = LockerType.new
  end

  def new
    @locker_type = LockerType.new
  end

  def create
    # the params might come with an :amount field, use that
    # to create locker instances
    @locker_type = LockerType.new(locker_type_params)
    if @locker_type.save!
      flash[:notice] = "Locker type #{@locker_type.short_form} created"
      redirect_to lockers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @locker_type = LockerType.find(params[:id])
  end

  def update
    @locker_type = LockerType.find(params[:id])
    if @locker_type.update(locker_type_params)
      redirect_to lockers_path, notice: "Locker updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @locker_type = LockerType.find(params[:id])
    if @locker_type.destroy
      flash[:notice] = "Locker type removed"
    else
      flash[
        :alert
      ] = "Failed to delete locker type, records probably exist in history"
    end
    redirect_to lockers_path
  end

  private

  def locker_type_params
    params.require(:locker_type).permit(
      :short_form,
      :description,
      :available,
      :available_for,
      :quantity,
      :cost
    )
  end
end
