class LockerTypesController < ApplicationController
  def index
  end

  def new
    @locker_type = LockerType.new
  end

  def create
    # the params might come with an :amount field, use that
    # to create locker instances
    @locker_type = LockerType.new(locker_type_params)
    if @locker_type.save
      flash[:notice] = "Locker type #{@locker_type.short_form} created"
      redirect_to lockers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
  end

  def destroy
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
