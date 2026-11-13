# frozen_string_literal: true

class Admin::SpacesController < AdminAreaController
  UNKNOWN_READERS_SHOWN = 50

  layout "admin_area"

  def index
  end

  #def new
  #  @space = Space.new
  #end

  def create
    space = Space.new(space_params)
    flash_write(space, "spaces.not_created", t("admin_area.spaces.flash.created")) { space.save_with_popular_hours }
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
      flash[:notice] = t("admin_area.spaces.flash.sub_space_created")
    else
      flash[:alert] = t("admin_area.spaces.flash.sub_space_name_missing")
    end
    redirect_back(fallback_location: root_path)
  end

  def delete_sub_space
    if params[:id].present?
      subspace = SubSpace.find(params[:id])
      if subspace.destroy
        flash[:notice] = t("admin_area.spaces.flash.sub_space_deleted")
      else
        flash[:alert] = subspace.errors.full_messages.to_sentence
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
        flash[:alert] = t("admin_area.spaces.flash.contact_info_missing")
        redirect_back(fallback_location: root_path)
        return
      end
      subspace.update(approval_required: !subspace.approval_required)
      flash[:notice] = t(subspace.approval_required ? "admin_area.spaces.flash.approval_manual" : "admin_area.spaces.flash.approval_automatic", name: subspace.name)
      redirect_back(
        fallback_location:
          edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
      )
    
  end

  def change_sub_space_default_public
    return unless params[:id].present?
      subspace = SubSpace.find(params[:id])
      subspace.update(default_public: !subspace.default_public)
      flash[:notice] = t(subspace.default_public ? "admin_area.spaces.flash.bookings_public" : "admin_area.spaces.flash.bookings_private", name: subspace.name)
      redirect_back(
        fallback_location:
          edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
      )
    
  end

  def edit
    @staff_needed_calendars = StaffNeededCalendar.where(space: params[:id])
    @new_training = Training.new
    @sub_spaces = SubSpace.where(space: Space.find(params[:id]))
    # readers seen tapping but not registered (those already in pi_readers show in the tables above)
    registered = PiReader.pluck(:pi_mac_address).filter_map { |mac| PiReader.normalize_mac(mac) }.to_set
    unknown = TapBoxLog.unknown_readers_seen.reject { |mac, _seen| registered.include?(mac) }
    @unknown_readers = unknown.first(UNKNOWN_READERS_SHOWN)
    @unknown_readers_more = unknown.size - @unknown_readers.size
    admins = User.where(role: "admin").order("LOWER(name) ASC")
    @admin_options = admins.map { |admin| [admin.name, admin.id] }
    @admin_options.unshift([t("admin_area.spaces.edit.select_admin"), -1])
    @space = Space.find(params[:id])
    count_training_records
  end

  def update_name
    @space = Space.find(params[:space_id])
    if @space.update(name: params[:name])
      flash[:notice] = t("admin_area.spaces.flash.name_updated")
    else
      flash[:alert] = space_name_error
    end
    redirect_back(fallback_location: root_path)
  end

  def update_max_capacity
    @space = Space.find(params[:space_id])
    max_capacity = params[:max_capacity].to_i
    max_capacity = nil if max_capacity.zero? # 0 is no limit
    flash_write(@space, "spaces.capacity_not_updated", t("admin_area.spaces.flash.capacity_updated")) { @space.update(max_capacity: max_capacity) }
    redirect_back(fallback_location: root_path)
  end

  def update_keycode
    @space = Space.find(params[:space_id])
    flash_write(@space, "spaces.keycode_not_updated", t("admin_area.spaces.flash.keycode_updated")) { @space.update(keycode: params[:keycode]) }
    redirect_back(fallback_location: root_path)
  end

  def add_space_manager
    if params[:space_manager_id].to_i == -1
      flash[:alert] = t("admin_area.spaces.flash.select_admin")
      redirect_back(fallback_location: admin_spaces_path)
      return
    end

    @space = Space.find(params[:space_id])
    @space_manager = User.find(params[:space_manager_id])
    space_manager_join =
      SpaceManagerJoin.new(user_id: @space_manager.id, space_id: @space.id)

    flash_write(space_manager_join, "spaces.manager_not_added", t("admin_area.spaces.flash.manager_added")) { space_manager_join.save }
    redirect_to admin_spaces_path
  end

  def remove_space_manager
    @space_manager_join =
      SpaceManagerJoin.find_by(id: params[:space_manager_join_id])

    if !@space_manager_join.nil?
      @space_manager_join.destroy
      redirect_to admin_spaces_path,
                  notice: t("admin_area.spaces.flash.manager_removed")
    else
      flash[:alert] = t("admin_area.spaces.flash.manager_missing")
      redirect_back(fallback_location: root_path)
    end
  end

  def set_max_booking_duration
    if params[:max_hours].present? && params[:sub_space_id].present?
      return update_sub_space_limit(:maximum_booking_duration, params[:max_hours], t("admin_area.spaces.flash.max_duration_updated"))
    end
    if params[:max_weekly_hours].present? && params[:sub_space_id].present?
      return(
        update_sub_space_limit(
          :maximum_booking_hours_per_week,
          params[:max_weekly_hours],
          t("admin_area.spaces.flash.max_weekly_updated")
        )
      )
    end
    flash[:alert] = I18n.t("errors.admin.spaces.booking_limit_missing")
    redirect_to edit_admin_space_path(id: params[:space_id])
  end

  def set_max_automatic_approval_hour
    if params[:auto_approve_hours].present? && params[:sub_space_id].present?
      return(
        update_sub_space_limit(
          :max_automatic_approval_hour,
          params[:auto_approve_hours],
          t("admin_area.spaces.flash.max_auto_updated")
        )
      )
    end
    flash[:alert] = I18n.t("errors.admin.spaces.approval_limit_missing")
    redirect_to edit_admin_space_path(id: params[:space_id])
  end

  def destroy
    space = Space.find(params[:id])
    if params[:admin_input] == space.name.upcase
      if space.destroy_admin_id.present? && space.destroy_admin_id != @user.id
        # The pi readers are detached only if the space is really deleted. A refusal (the space still has
        # history it must not lose) is the model's, so its errors say why; the pending request is cleared.
        deleted = Space.transaction do
          PiReader.where(space_id: space.id).update_all(space_id: nil)
          space.destroy || raise(ActiveRecord::Rollback)
        end
        if deleted
          flash[:notice] = t("admin_area.spaces.flash.deleted")
        else
          space.update_columns(destroy_admin_id: nil)
          flash[:alert] = validation_message(space, "errors.admin.spaces.not_deleted")
        end
      elsif (refusals = space.deletion_refusals).any?
        # Said at the first request, so nobody waits for a second admin to be told, and no request is recorded.
        space.update_columns(destroy_admin_id: nil) if space.destroy_admin_id.present?
        flash[:alert] = refusals.to_sentence
      elsif space.update(
          destroy_admin_id: @user.id
        )
        flash[:notice] = t("admin_area.spaces.flash.destroy_requested")
      end
    else
      flash[:alert] = I18n.t("errors.admin.spaces.confirmation_mismatch")
    end
    redirect_to admin_spaces_path
  end

  def update_staff_needed_calendars
    unless params[:space_id].present?
      flash[:alert] = I18n.t("errors.admin.spaces.calendar_space_missing")
      return redirect_back(fallback_location: root_path)
    end

    calendar_urls = Array(params[:staff_needed_calendar])
    calendar_names = Array(params[:staff_needed_calendar_name])
    calendar_colors = Array(params[:staff_needed_calendar_color])
    calendar_roles = Array(params[:staff_needed_calendar_role])

    open_hours_count = calendar_roles.count { |r| r == "open_hours" }
    if open_hours_count > 1
      flash[:alert] = t("admin_area.spaces.flash.one_open_hours")
      return redirect_back(fallback_location: root_path)
    end

    begin
      StaffNeededCalendar.transaction do
        StaffNeededCalendar.where(space_id: params[:space_id]).destroy_all

        calendar_urls.each_with_index do |url, i|
          next if url.blank?

          StaffNeededCalendar.create!(
            name: calendar_names[i],
            color: calendar_colors[i],
            role: calendar_roles[i].presence,
            space_id: params[:space_id],
            calendar_url: url
          )
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = validation_message(e.record, "failed_saves.calendars")
      return redirect_back(fallback_location: root_path)
    end

    flash[:notice] = t("admin_area.spaces.flash.calendars_updated")
    redirect_back(fallback_location: root_path)
  end

  def update_sub_space
    sub_space = SubSpace.find(params[:id])
    old_name = sub_space.name

    if params[:name].blank?
      flash[:alert] = t("admin_area.spaces.flash.sub_space_name_blank")
    elsif sub_space.update(name: params[:name])
      flash[:notice] = t("admin_area.spaces.flash.sub_space_renamed", old: old_name, new: sub_space.name)
    else
      flash[:alert] = validation_message(sub_space, "errors.admin.spaces.sub_space_not_renamed")
    end

    redirect_back(
      fallback_location: edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
    )
  end

  private

  # Sessions and active certifications of each training offered in the space, over every space,
  # counted in two queries for the trainings table.
  def count_training_records
    training_ids = @space.trainings.select(:id)
    @session_counts = TrainingSession.reorder(nil).where(training_id: training_ids).group(:training_id).count
    @certification_counts = Certification.joins(:training_session).where(training_sessions: { training_id: training_ids })
                                         .group("training_sessions.training_id").count
  end

  # Sets one hours limit of a sub space from the submitted text: a whole number of hours, or -1 to remove the limit.
  def update_sub_space_limit(attribute, text, notice)
    unless text.to_s.match?(/\A(-1|\d+)\z/)
      flash[:alert] = I18n.t("errors.admin.spaces.limit_not_whole_number")
      return redirect_to edit_admin_space_path(id: params[:space_id])
    end
    hours = text.to_i
    SubSpace.find(params[:sub_space_id]).update!(attribute => hours == -1 ? nil : hours)
    flash[:notice] = notice
    redirect_to edit_admin_space_path(id: params[:space_id], anchor: "sub_space_area")
  end

  def space_name_error
    kind = @space.errors.of_kind?(:name, :blank) ? "blank" : "taken"
    t("admin.space_name.#{kind}")
  end

  def space_params
    params.require(:space_params).permit(:name, :max_capacity, :keycode)
  end
end
