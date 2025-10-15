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
        params[:approval_required] == "1"
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
    return unless params[:id].present?
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

  def change_sub_space_default_public
    return unless params[:id].present?
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

  def edit
    @staff_needed_calendars = StaffNeededCalendar.where(space: params[:id])
    @space_staff_hours = SpaceStaffHour.where(space: params[:id])
    @new_training = Training.new
    @sub_spaces = SubSpace.where(space: Space.find(params[:id]))
    admins = User.where(role: "admin").order("LOWER(name) ASC")
    @admin_options = admins.map { |admin| [admin.name, admin.id] }
    @admin_options.unshift(["Select an Admin", -1])

    return if @space = Space.find(params[:id])
      flash[:alert] = "Not Found"
      redirect_back(fallback_location: root_path)
    
  end

  def update_name
    @space = Space.find(params[:space_id])
    return unless @space.update(name: params[:name])
      flash[:notice] = "Space Name updated !"
      redirect_back(fallback_location: root_path)
    
  end

  def update_max_capacity
    @space = Space.find(params[:space_id])
    max_capacity = params[:max_capacity].to_i
    max_capacity = nil if max_capacity.zero? # 0 is no limit
    if @space.update(max_capacity: params[:max_capacity])
      flash[:notice] = "Space Capacity updated!"
    else
      flash[:alert] = "Failed to update space capacity."
    end
    redirect_back(fallback_location: root_path)
  end

  def update_keycode
    @space = Space.find(params[:space_id])
    return unless @space.update(keycode: params[:keycode])
      flash[:notice] = "Space keycode updated!"
      redirect_back(fallback_location: root_path)
    
  end

  def add_space_manager
    if params[:space_manager_id].to_i == -1
      flash[:alert] = "Please select an admin"
      redirect_back(fallback_location: admin_spaces_path)
      return
    end

    @space = Space.find(params[:space_id])
    @space_manager = User.find(params[:space_manager_id])
    space_manager_join =
      SpaceManagerJoin.new(user_id: @space_manager.id, space_id: @space.id)

    if space_manager_join.save
      flash[:notice] = "Successfully added space manager"
    else
      flash[:alert] = "Failed to add space manager"
    end
    redirect_to admin_spaces_path
  end

  def remove_space_manager
    @space_manager_join =
      SpaceManagerJoin.find_by(id: params[:space_manager_join_id])

    if !@space_manager_join.nil?
      @space_manager_join.destroy
      redirect_to admin_spaces_path,
                  notice: "Successfully removed space manager"
    else
      flash[:alert] = "Cannot find space manager"
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
    flash[:notice] = if training_level.save
      "Training Level added !"
    else
      "An issue occurred while adding the training level."
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
      elsif space.update(
          destroy_admin_id: @user.id
        )
        flash[
          :notice
        ] = "The destroy request has been submitted, a second admin will need to approve it for the space to be destroyed."
      end
    else
      flash[:alert] = "Invalid Input"
    end
    redirect_to admin_spaces_path
  end

  def update_staff_needed_calendars
    unless params[:space_id].present?
      flash[:alert] = "An error occurred while trying to add/remove the calendar URLs, please try again later."
      return redirect_back(fallback_location: root_path)
    end

    calendar_urls = Array(params[:staff_needed_calendar])
    calendar_names = Array(params[:staff_needed_calendar_name])
    calendar_colors = Array(params[:staff_needed_calendar_color])
    calendar_roles = Array(params[:staff_needed_calendar_role])

    open_hours_count = calendar_roles.count { |r| r == "open_hours" }
    if open_hours_count > 1
      flash[:alert] = "Only one calendar can be assigned the 'open_hours' role."
      return redirect_back(fallback_location: root_path)
    end

    StaffNeededCalendar.where(space_id: params[:space_id]).destroy_all

    calendar_urls.each_with_index do |url, i|
      next if url.blank?

      snc = StaffNeededCalendar.create(
        name: calendar_names[i],
        color: calendar_colors[i],
        role: calendar_roles[i].presence,
        space_id: params[:space_id],
        calendar_url: url
      )
      # Copy over to MakerRoom
      space = Space.find(params[:space_id])
      if space.id == 24 && calendar_roles[i] == "makeroom"
        helpers.create_makeroom_bookings_from_ics(snc)
        Rails.logger.debug "_________________________________________________________"
      end
    end    

    flash[:notice] = "Calendars updated successfully."
    redirect_back(fallback_location: root_path)
  end

  private

  def space_params
    params.require(:space_params).permit(:name, :max_capacity, :keycode)
  end
end
