# app/controllers/staff/unavailabilities_controller.rb
class Staff::UnavailabilitiesController < StaffAreaController
  include CalendarWindowed
  include CalendarDialog
  layout "staff_area"

  def index
    @external_unavailabilities = StaffExternalUnavailability.where(user_id: current_user.id)
  end

  def create
    start, finish = dialog_times
    @staff_unavailability = StaffUnavailability.new(
      **dialog_fields(default_title),
      start_time: start,
      end_time: finish,
      recurrence_rule: staff_params[:recurrence_rule].presence,
      user_id: target_user.id
    )

    dialog_saved(@staff_unavailability.save, "Unavailability created#{" for #{target_user.name}" if admin_managing_other_user?}.",
                 @staff_unavailability, "failed_saves.unavailability_create")
  end

  def update
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)

    # Check if trying to change event type (not allowed for unavailabilities)
    if params[:staff_unavailability][:event_type].present? && 
       params[:staff_unavailability][:event_type] != "unavailability"
      return dialog_done(alert: "Cannot change an unavailability to another event type.")
    end

    update_scope = @staff_unavailability.recurrence_rule.present? ? params[:update_scope] : "non-recurring"

    case update_scope
    when "non-recurring" then update_single_unavailability
    when "all" then update_all_occurrences
    when "this" then update_this_occurrence
    else dialog_done(alert: "Invalid update scope.")
    end
  end

  def destroy
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)
    remove_unavailability("Unavailability deleted.")
  end

  def delete_with_scope
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)
    return remove_unavailability("Unavailability deleted.") if @staff_unavailability.recurrence_rule.blank?

    case params[:scope]
    when "single"
      shorten_unavailability_series("This occurrence deleted.", :without_occurrence, "Start date is required for deleting a single occurrence.")
    when "following"
      shorten_unavailability_series("This and following deleted.", :ending_before, "Start date is required for deleting following occurrences.")
    when "all" then remove_unavailability("All occurrences deleted.")
    else
      Rails.logger.error "Invalid scope received: #{params[:scope]}"
      dialog_done(alert: "Invalid delete scope: #{params[:scope]}")
    end
  rescue ActiveRecord::RecordInvalid => e
    dialog_done(alert: validation_message(e.record, "failed_saves.unavailability_update"))
  end

  # The occurrences in the window (CalendarWindow, required) of the staff member's own unavailabilities and of
  # those of their linked calendars.
  def json
    window = CalendarWindow.bounded(params)
    name = StaffExternalUnavailability.display_name_for(current_user.name)
    calendars = current_user.staff_external_unavailabilities.map { |external| [external, external.fetch_calendar(name:)] }
    report_failed_calendars(calendars)

    render json: own_unavailability_rows(window) + calendars.flat_map { |external, calendar|
      # only the host is ever sent: a private link holds its secret in the path
      calendar.feed_rows(window, prefix: "External - ", props: { sourceHost: external.source_host })
    }
  end

  def update_external_unavailabilities
    calendars = Array(params[:external_calendar]).compact_blank.map(&:to_s)
    records = calendars.map { |url| StaffExternalUnavailability.new(user_id: current_user.id, ics_url: url) }

    # Nothing is replaced unless every link is usable.
    if (invalid = records.find(&:invalid?))
      return redirect_to staff_unavailabilities_path,
                         alert: "#{invalid.ics_url.truncate(80)} is not an http or https link. Nothing was changed."
    end

    StaffExternalUnavailability.transaction do
      StaffExternalUnavailability.where(user_id: current_user.id).destroy_all
      records.each(&:save!)
    end

    redirect_to staff_unavailabilities_path, notice: "External calendar links updated."
  end

  private

  def own_unavailability_rows(window)
    window.records(StaffUnavailability.where(user_id: current_user.id)).flat_map do |unavailability|
      unavailability.feed_rows(window, title: unavailability.title || "Unavailable", extendedProps: { description: unavailability.description })
    end
  end

  # The hosts of the linked calendars that could not be loaded go in a header, a JSON list (null for a link whose
  # host cannot be read). The header is not part of the body's ETag, so a browser must not reuse an earlier answer.
  def report_failed_calendars(calendars)
    failed_hosts = calendars.select { |_external, calendar| calendar.failed? }.map { |external, _calendar| external.source_host }
    response.set_header("Cache-Control", "no-store")
    response.set_header("X-Failed-Calendars", failed_hosts.to_json) unless failed_hosts.empty?
  end

  def staff_params
    params.require(:staff_unavailability).permit(
      :user_id, :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule, :event_type
    )
  end

  # Returns the user whose unavailability is being managed
  def target_user
    @target_user ||= if admin_managing_other_user?
      # Use the safe navigation operator or fallback to params
      user_id = @staff_unavailability&.user_id || staff_params[:user_id]
      User.find(user_id)
    else
      current_user
    end
  end

  # Can the current user manage another user's unavailabilities?
  def admin_managing_other_user?
    return false unless current_user.admin?

    # If we are working on an existing record (Edit, Update, Delete)
    if @staff_unavailability.present?
      return @staff_unavailability.user_id != current_user.id
    end
    
    # If we are creating a new record (Create), check raw params safely
    # We access params directly here to avoid the 'param is missing' error from strong params
    if params[:staff_unavailability].present? && params[:staff_unavailability][:user_id].present?
      return params[:staff_unavailability][:user_id].to_i != current_user.id
    end

    false
  end

  # Ensure user can only edit their own unavailabilities (unless admin)
  def authorize_unavailability!(unavailability)
    return if current_user.admin?
    return if unavailability.user_id == current_user.id

    raise ActiveRecord::RecordNotFound
  end

  # The title (a blank one becomes `default`) and the description, which is kept as plain text.
  def dialog_fields(default = "Unavailable")
    { title: staff_params[:title].presence || default, description: ActionController::Base.helpers.strip_tags(staff_params[:description].to_s) }
  end

  def default_title
    admin_managing_other_user? ? "Unavailable (Admin)" : "Unavailable"
  end

  def after_dialog_path
    # If the user was on an admin page (like the Admin Calendar), send them back there.
    # This handles the case where an Admin edits their OWN unavailability from the Admin Calendar.
    if current_user.admin? && request.referer.to_s.match?(/admin/)
      return admin_calendar_index_path
    end

    # If explicitly managing another user (and referer check failed for some reason)
    if admin_managing_other_user?
      admin_calendar_index_path
    else
      # Default for standard staff usage
      staff_unavailabilities_path
    end
  end

  def update_single_unavailability
    start, finish = @staff_unavailability.times_after_update(*dialog_times, keep: keep_dialog_times?)
    saved = @staff_unavailability.update(**dialog_fields, start_time: start, end_time: finish,
                                                          recurrence_rule: staff_params[:recurrence_rule].presence)
    dialog_saved(saved, "Unavailability updated successfully.", @staff_unavailability, "failed_saves.unavailability_update")
  end

  def update_all_occurrences
    return alert_unreadable_times if unreadable_times?

    start, finish = @staff_unavailability.times_after_update(*dialog_times, keep: keep_dialog_times?, series: true)
    rule_to_use = series_rule(@staff_unavailability).with_time_from(staff_params[:recurrence_rule], at: start)

    saved = @staff_unavailability.update(**dialog_fields, start_time: start, end_time: finish, recurrence_rule: rule_to_use)
    dialog_saved(saved, "All occurrences updated successfully.", @staff_unavailability, "failed_saves.unavailability_update")
  end

  # Whether the dialog sent its time fields as it filled them from the clicked entry.
  def keep_dialog_times?
    params[:keep_series_times] == "1"
  end

  def update_this_occurrence
    return alert_unreadable_times if unreadable_times?

    excluded, start, finish = @staff_unavailability.occurrence_after_update(*dialog_times, keep: keep_dialog_times?)
    updated_rule = series_rule(@staff_unavailability).appending_exdate(excluded)

    unless @staff_unavailability.update(recurrence_rule: updated_rule)
      return dialog_done(alert: validation_message(@staff_unavailability, "failed_saves.unavailability_update"))
    end

    StaffUnavailability.create!(
      **dialog_fields,
      start_time: start,
      end_time: finish,
      recurrence_rule: nil,
      user_id: @staff_unavailability.user_id
    )

    dialog_done(notice: "This occurrence updated successfully.")
  end

  def remove_unavailability(notice)
    @staff_unavailability.destroy
    dialog_done(notice: notice)
  end

  def shorten_unavailability_series(notice, change, start_missing)
    return dialog_done(alert: start_missing) unless shorten_series(@staff_unavailability, change)

    dialog_done(notice: notice)
  end

  def series_rule(unavailability)
    RecurrenceRule.new(unavailability.recurrence_rule, unavailability.start_time)
  end

  # The posted start and end as UTC times; nil for one that is missing or not a time.
  def dialog_times
    [parse_time(staff_params[:utc_start_time]), parse_time(staff_params[:utc_end_time])]
  end

  def unreadable_times?
    dialog_times.any?(&:nil?)
  end

  # The model's blank-time messages for a series edit that has no usable start or end.
  def alert_unreadable_times
    record = StaffUnavailability.new
    start, finish = dialog_times
    record.errors.add(:start_time, :blank) if start.nil?
    record.errors.add(:end_time, :blank) if finish.nil?
    dialog_done(alert: validation_message(record, "failed_saves.unavailability_update"))
  end
end