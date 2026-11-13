# app/controllers/staff/unavailabilities_controller.rb
class Staff::UnavailabilitiesController < StaffAreaController
  include CalendarWindowed
  layout "staff_area"

  def index
    @external_unavailabilities = StaffExternalUnavailability.where(user_id: current_user.id)
  end

  def create
    @staff_unavailability = StaffUnavailability.new(
      title: staff_params[:title].presence || default_title,
      description: ActionController::Base.helpers.strip_tags(staff_params[:description].to_s),
      start_time: parse_time(staff_params[:utc_start_time]),
      end_time: parse_time(staff_params[:utc_end_time]),
      recurrence_rule: staff_params[:recurrence_rule].presence,
      user_id: target_user.id
    )

    if @staff_unavailability.save
      flash[:notice] = "Unavailability created#{" for #{target_user.name}" if admin_managing_other_user?}."
    else
      flash[:alert] = validation_message(@staff_unavailability, "failed_saves.unavailability_create")
    end

    redirect_to after_action_path
  end

  def update
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)

    # Check if trying to change event type (not allowed for unavailabilities)
    if params[:staff_unavailability][:event_type].present? && 
       params[:staff_unavailability][:event_type] != "unavailability"
      flash[:alert] = "Cannot change an unavailability to another event type."
      return redirect_to after_action_path
    end

    update_scope = @staff_unavailability.recurrence_rule.present? ? params[:update_scope] : "non-recurring"

    case update_scope
    when "non-recurring"
      update_single_unavailability
    when "all"
      update_all_occurrences
    when "this"
      update_this_occurrence
    else
      flash[:alert] = "Invalid update scope."
    end

    redirect_to after_action_path
  end

  def destroy
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)
    @staff_unavailability.destroy

    redirect_to after_action_path, notice: "Unavailability deleted."
  end

  def delete_with_scope
    @staff_unavailability = StaffUnavailability.find(params[:id])
    authorize_unavailability!(@staff_unavailability)
    scope = params[:scope]

    Rails.logger.info "=== DELETE_WITH_SCOPE ==="
    Rails.logger.info "Unavailability ID: #{@staff_unavailability.id}"
    Rails.logger.info "Scope: #{scope}"
    Rails.logger.info "Start Date: #{params[:start_date]}"
    Rails.logger.info "Recurrence Rule: #{@staff_unavailability.recurrence_rule.inspect}"
    Rails.logger.info "========================"

    if @staff_unavailability.recurrence_rule.blank?
      @staff_unavailability.destroy
      return redirect_to after_action_path, notice: "Unavailability deleted."
    end

    case scope
    when "single"
      delete_single_occurrence
    when "following"
      delete_following_occurrences
    when "all"
      @staff_unavailability.destroy
      redirect_to after_action_path, notice: "All occurrences deleted."
    else
      Rails.logger.error "Invalid scope received: #{scope}"
      redirect_to after_action_path, alert: "Invalid delete scope: #{scope}"
    end
  end

  # The occurrences in the window (CalendarWindow, required) of the staff member's own unavailabilities and of
  # those of their linked calendars.
  def json
    window = CalendarWindow.bounded(params)
    name = "#{current_user.name} External Unavailability"
    calendars = current_user.staff_external_unavailabilities.map { |external| [external, external.calendar(name: name)] }
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

  def default_title
    admin_managing_other_user? ? "Unavailable (Admin)" : "Unavailable"
  end

  def after_action_path
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
    if @staff_unavailability.update(
        title: staff_params[:title].presence || "Unavailable",
        description: ActionController::Base.helpers.strip_tags(staff_params[:description].to_s),
        start_time: parse_time(staff_params[:utc_start_time]),
        end_time: parse_time(staff_params[:utc_end_time]),
        recurrence_rule: staff_params[:recurrence_rule].presence
      )
      flash[:notice] = "Unavailability updated successfully."
    else
      flash[:alert] = validation_message(@staff_unavailability, "failed_saves.unavailability_update")
    end
  end

  def update_all_occurrences
    return alert_unreadable_times if unreadable_times?

    start, finish = series_times
    rule_to_use = series_rule(@staff_unavailability).with_time_from(staff_params[:recurrence_rule], at: start)

    if @staff_unavailability.update(
        title: staff_params[:title].presence || "Unavailable",
        description: ActionController::Base.helpers.strip_tags(staff_params[:description].to_s),
        start_time: start,
        end_time: finish,
        recurrence_rule: rule_to_use
      )
      flash[:notice] = "All occurrences updated successfully."
    else
      flash[:alert] = validation_message(@staff_unavailability, "failed_saves.unavailability_update")
    end
  end

  # The series' start and end after "update all": its own when the dialog sends its times as it filled them
  # (keep_series_times), else the series' Toronto start date at the posted Toronto clock time, for the posted length.
  def series_times
    return [@staff_unavailability.start_time, @staff_unavailability.end_time] if params[:keep_series_times] == "1"

    posted_start = parse_time(staff_params[:utc_start_time])
    start = helpers.combine_date_and_time(@staff_unavailability.start_time, posted_start)
    [start, start + (parse_time(staff_params[:utc_end_time]) - posted_start).to_i]
  end

  def update_this_occurrence
    return alert_unreadable_times if unreadable_times?

    exclusion_start_time = helpers.combine_date_and_time(
      parse_time(staff_params[:utc_start_time]),
      @staff_unavailability.start_time
    )

    updated_rule = series_rule(@staff_unavailability).appending_exdate(exclusion_start_time)

    unless @staff_unavailability.update(recurrence_rule: updated_rule)
      flash[:alert] = validation_message(@staff_unavailability, "failed_saves.unavailability_update")
      return
    end

    StaffUnavailability.create!(
      title: staff_params[:title].presence || "Unavailable",
      description: ActionController::Base.helpers.strip_tags(staff_params[:description].to_s),
      start_time: parse_time(staff_params[:utc_start_time]),
      end_time: parse_time(staff_params[:utc_end_time]),
      recurrence_rule: nil,
      user_id: @staff_unavailability.user_id
    )

    flash[:notice] = "This occurrence updated successfully."
  end

  def delete_single_occurrence
    start = parse_time(params[:start_date])
    if start.nil?
      return redirect_to after_action_path, alert: "Start date is required for deleting a single occurrence."
    end

    @staff_unavailability.update!(recurrence_rule: series_rule(@staff_unavailability).without_occurrence(start))
    redirect_to after_action_path, notice: "This occurrence deleted."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to after_action_path, alert: validation_message(e.record, "failed_saves.unavailability_update")
  end

  def delete_following_occurrences
    start = parse_time(params[:start_date])
    if start.nil?
      return redirect_to after_action_path, alert: "Start date is required for deleting following occurrences."
    end

    @staff_unavailability.update!(recurrence_rule: series_rule(@staff_unavailability).ending_before(start))
    redirect_to after_action_path, notice: "This and following deleted."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to after_action_path, alert: validation_message(e.record, "failed_saves.unavailability_update")
  end

  def series_rule(unavailability)
    RecurrenceRule.new(unavailability.recurrence_rule, unavailability.start_time)
  end

  # The time as UTC, or nil when the text is missing or not a time.
  def parse_time(time_string)
    return nil if time_string.blank?
    Time.parse(time_string).utc
  rescue ArgumentError
    nil
  end

  def unreadable_times?
    parse_time(staff_params[:utc_start_time]).nil? || parse_time(staff_params[:utc_end_time]).nil?
  end

  # The model's blank-time messages for a series edit that has no usable start or end.
  def alert_unreadable_times
    record = StaffUnavailability.new
    record.errors.add(:start_time, :blank) if parse_time(staff_params[:utc_start_time]).nil?
    record.errors.add(:end_time, :blank) if parse_time(staff_params[:utc_end_time]).nil?
    flash[:alert] = validation_message(record, "failed_saves.unavailability_update")
  end
end