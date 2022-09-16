# frozen_string_literal: true

class Admin::SpacesController < AdminAreaController
  layout "admin_area"

  def index
  end

  #def new
  #  @space = Space.new
  #end

  def create
    space = Space.new(space_params)
    if space.save
      flash[:notice] = "Space created successfully!"
    else
      flash[:alert] = "Something went wrong."
    end

    redirect_back(fallback_location: root_path)
  end

  def create_sub_space
    if params[:name].present?
      SubSpace.create(name: params[:name], space: Space.find(params[:space_id]))
      flash[:notice] = "Sub Space created!"
    else
      flash[:alert] = "Please enter a name for the sub space"
    end
    redirect_back(fallback_location: root_path)
  end

  def delete_sub_space
    if params[:name].present?
      if SubSpace.where(
           name: params[:name],
           space: Space.find(params[:space_id])
         ).destroy_all
        flash[:notice] = "Sub Space deleted!"
      else
        flash[:alert] = "Something went wrong."
      end
    end
    @sub_spaces = SubSpace.where(space: Space.find(params[:space_id]))
    redirect_back(fallback_location: root_path)
  end

  def edit
    @space_staff_hours = SpaceStaffHour.where(space: params[:id])
    @new_training = Training.new
    @sub_spaces = SubSpace.where(space: Space.find(params[:id]))
    unless @space = Space.find(params[:id])
      flash[:alert] = "Not Found"
      redirect_back(fallback_location: root_path)
    end
  end

  def update_name
    @space = Space.find(params[:space_id])
    if @space.update(name: params[:name])
      flash[:notice] = "Space Name updated !"
      redirect_back(fallback_location: root_path)
    end
  end

  def update_max_capacity
    @space = Space.find(params[:space_id])
    if @space.update(max_capacity: params[:max_capacity])
      flash[:notice] = "Space Capacity updated !"
      redirect_back(fallback_location: root_path)
    end
  end

  def add_space_hours
    unless params[:space_id].present? && params[:day].present? &&
             params[:start_time].present? && params[:end_time].present? &&
             SpaceStaffHour.create(
               space_id: params[:space_id],
               day: params[:day],
               start_time: params[:start_time],
               end_time: params[:end_time]
             )
      flash[:notice] = "Make sure you sent all the information and try again."
    end
    redirect_back(fallback_location: root_path)
  end

  def delete_space_hour
    unless params[:space_staff_hour_id] &&
             SpaceStaffHour.find(params[:space_staff_hour_id]).present? &&
             SpaceStaffHour.find(params[:space_staff_hour_id]).destroy
      flash[:notice] = "An issue occurred while deleting the slot."
    end
    redirect_back(fallback_location: root_path)
  end

  def destroy
    space = Space.find(params[:id])
    if params[:admin_input] == space.name.upcase
      if space.destroy_admin_id.present? && space.destroy_admin_id != @user.id
        raspis = PiReader.where(space_id: space.id)
        raspis.update_all(space_id: nil)
        flash[:notice] = "Space deleted!" if space.destroy
      else
        flash[
          :notice
        ] = "The destroy request has been submitted, a second admin will need to approve it for the space to be destroyed." if space.update(
          destroy_admin_id: @user.id
        )
      end
    else
      flash[:alert] = "Invalid Input"
    end
    redirect_to admin_spaces_path
  end

  private

  def space_params
    params.require(:space_params).permit(:name, :max_capacity)
  end
end
