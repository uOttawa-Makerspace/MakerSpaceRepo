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
      sub_space =
        SubSpace.create(
          name: params[:name],
          space: Space.find(params[:space_id])
        )
      sub_space.approval_required =
        params[:approval_required] == "1" ? true : false
      sub_space.save
      flash[:notice] = "Sub Space created!"
    else
      flash[:alert] = "Please enter a name for the sub space"
    end
    redirect_back(fallback_location: root_path)
  end

  def delete_sub_space
    if params[:id].present?
      subspace = SubSpace.find(params[:id])
      SubSpaceBooking
        .where(sub_space: subspace)
        .each do |booking|
          status =
            SubSpaceBookingStatus.find(booking.sub_space_booking_status_id)
          status.update(sub_space_booking_id: nil)
          booking.update(sub_space_booking_status_id: nil)
          status.destroy
          booking.destroy
        end
      if subspace.delete
        flash[:notice] = "Sub Space deleted!"
      else
        flash[:alert] = "Something went wrong."
      end
    end
    @sub_spaces =
      SubSpace.where(space: Space.find(params[:space_id])).order(:name)
    redirect_back(
      fallback_location: edit_admin_space_path(id: params[:space_id])
    )
  end

  def change_sub_space_approval
    if params[:id].present?
      subspace = SubSpace.find(params[:id])
      if ContactInfo.where(space_id: subspace.space.id).blank?
        flash[
          :alert
        ] = "Please add contact information for the associated space disabling automatic booking."
        redirect_back(fallback_location: root_path)
        return
      end
      subspace.update(approval_required: !subspace.approval_required)
      flash[
        :notice
      ] = "Aproval for #{subspace.name} is now #{subspace.approval_required ? "manual" : "automatic"}"
      redirect_back(
        fallback_location:
          edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
      )
    end
  end

  def change_sub_space_default_public
    if params[:id].present?
      subspace = SubSpace.find(params[:id])
      subspace.update(default_public: !subspace.default_public)
      flash[
        :notice
      ] = "Bookings in #{subspace.name} are #{subspace.default_public ? "public" : "private"} by default"
      redirect_back(
        fallback_location:
          edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
      )
    end
  end

  def edit
    @staff_needed_calendars = StaffNeededCalendar.where(space: params[:id])
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
             params[:language].present? && params[:training_course].present? &&
             params[:training_level].present?
      flash[:notice] = "Make sure you sent all the information and try again."
      redirect_to edit_admin_space_path(
                    params[:space_id],
                    fallback_location: root_path
                  )
    end
    SpaceStaffHour.create(
      space_id: params[:space_id],
      day: params[:day],
      start_time: params[:start_time],
      end_time: params[:end_time],
      language: params[:language],
      course_name_id: CourseName.find(params[:training_course]).id,
      training_level_id: TrainingLevel.find(params[:training_level]).id
    )
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
  def set_max_booking_duration
    if params[:max_hours].present? && params[:sub_space_id].present?
      SubSpace.find(params[:sub_space_id]).update!(
        maximum_booking_duration:
          params[:max_hours].to_i == -1 ? nil : params[:max_hours].to_i
      )
      flash[:notice] = "Max booking duration updated!"
      redirect_to edit_admin_space_path(
                    id: params[:space_id],
                    anchor: "sub_space_area"
                  )
      return
    end
    if params[:max_weekly_hours].present? && params[:sub_space_id].present?
      SubSpace.find(params[:sub_space_id]).update!(
        maximum_booking_hours_per_week:
          (
            if params[:max_weekly_hours].to_i == -1
              nil
            else
              params[:max_weekly_hours].to_i
            end
          )
      )
      flash[:notice] = "Max weekly booking duration updated!"
      redirect_to edit_admin_space_path(
                    id: params[:space_id],
                    anchor: "sub_space_area"
                  )
      return
    end
    flash[:alert] = "Something went wrong."
    redirect_to edit_admin_space_path(id: params[:space_id])
  end

  def set_max_automatic_approval_hour
    if params[:auto_approve_hours].present? && params[:sub_space_id].present?
      SubSpace.find(params[:sub_space_id]).update!(
        max_automatic_approval_hour:
          (
            if params[:auto_approve_hours].to_i == -1
              nil
            else
              params[:auto_approve_hours].to_i
            end
          )
      )
      flash[:notice] = "Max automatic approval duration updated!"
      redirect_to edit_admin_space_path(
                    id: params[:space_id],
                    anchor: "sub_space_area"
                  )
      return
    end
    flash[:alert] = "Something went wrong."
    redirect_to edit_admin_space_path(id: params[:space_id])
  end

  def add_training_levels
    unless params[:space_id].present? && params[:name].present?
      flash[:notice] = "Make sure you sent all the information and try again."
      redirect_to edit_admin_space_path(
                    params[:space_id],
                    fallback_location: root_path
                  )
    end
    training_level =
      TrainingLevel.new(
        space: Space.find(params[:space_id]),
        name: params[:name]
      )
    if training_level.save
      flash[:notice] = "Training Level added !"
    else
      flash[:notice] = "An issue occurred while adding the training level."
    end
    redirect_to edit_admin_space_path(
                  params[:space_id],
                  fallback_location: root_path
                )
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

  def update_staff_needed_calendars
    unless params[:space_id].present?
      flash[
        :alert
      ] = "An error occurred while trying to add/remove the calendar URLs, please try again later."
    end
    StaffNeededCalendar.where(space_id: params[:space_id]).destroy_all
    (
      if (params[:staff_needed_calendar].is_a? Array)
        params[:staff_needed_calendar]
      else
        [params[:staff_needed_calendar]]
      end
    ).each_with_index do |snc, i|
      unless snc.blank?
        StaffNeededCalendar.create(
          color:
            (
              if (params[:staff_needed_calendar_color].is_a? Array)
                params[:staff_needed_calendar_color][i]
              else
                params[:staff_needed_calendar_color]
              end
            ),
          space_id: params[:space_id],
          calendar_url: snc
        )
      end
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def space_params
    params.require(:space_params).permit(:name, :max_capacity)
  end
end
