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
      flash[:notice] = I18n.t("admin_pages.drop_off_locations.flash.added")
    else
      flash[:alert] = I18n.t("admin_pages.drop_off_locations.flash.invalid")
    end
    redirect_to admin_drop_off_locations_path
  end

  def update
    if @location.update(params.expect(drop_off_location: [:name]))
      flash[:notice] = I18n.t("admin_pages.drop_off_locations.flash.renamed")
    else
      flash[:alert] = I18n.t("admin_pages.drop_off_locations.flash.invalid")
    end
    redirect_to admin_drop_off_locations_path
  end

  def destroy
    if @location.destroy
      flash[:notice] = I18n.t("admin_pages.drop_off_locations.flash.deleted")
    else
      flash[:alert] = I18n.t("admin_pages.drop_off_locations.flash.not_deleted")
    end
    redirect_to admin_drop_off_locations_path
  end

  private

  def drop_off_location_params
    params.permit(:name, drop_off_location: [:name])
  end

  def set_location
    @location = DropOffLocation.find(params[:id])
  end
end
