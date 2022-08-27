class Admin::DropOffLocationsController < AdminAreaController
  before_action :set_location, only: %i[edit update destroy]

  def index
    @locations = DropOffLocation.all
  end

  def new
    @new_location = DropOffLocation.new
  end

  def edit
  end

  def create
    @new_location = DropOffLocation.new(drop_off_location_params)
    if @new_location.save
      flash[:notice] = "Drop-off Location added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_drop_off_locations_path
  end

  def update
    @location.update(drop_off_location_params)
    if @location.save
      flash[:notice] = "Drop-off Location renamed successfully"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_drop_off_locations_path
  end

  def destroy
    if @location.destroy
      flash[:notice] = "Drop-off Location Deleted successfully"
    else
      flash[:alert] = "An error occured while deleting the Drop-off Location."
    end
    redirect_to admin_drop_off_locations_path
  end

  private

  def drop_off_location_params
    params.require(:drop_off_location).permit(:name)
  end

  def set_location
    @location = DropOffLocation.find(params[:id])
  end
end
