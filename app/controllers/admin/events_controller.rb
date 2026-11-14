class Admin::EventsController < AdminAreaController
  include CalendarWindowed
  include CalendarDialog
  layout "admin_area"

  before_action :parse_event_times, only: %i[create update]
  before_action :parse_view_range, if: :view_range_action?

  def create
    @event = Event.new(**dialog_fields, space_id: event_params[:space_id], recurrence_rule: event_params[:recurrence_rule].presence,
                                        start_time: @start_time, end_time: @end_time, created_by_id: current_user.id)
    assignments = Array.wrap(params[:staff_select].presence).map { |staff_id| EventAssignment.new(event: @event, user_id: staff_id) }

    saved = @event.save && assignments.all?(&:save)
    @event.push_to_google_later if @event.persisted?

    dialog_saved(saved, "Event created successfully.", @event, "failed_saves.event_create")
  end

  def update
    @event = Event.find(params[:id])
    participants = Array.wrap(params[:staff_select].presence)
    update_scope = @event.recurrence_rule.present? ? params[:update_scope] : "non-recurring"

    case update_scope
    when "non-recurring"
      start_time, end_time = @event.times_after_update(@start_time, @end_time, keep: keep_dialog_times?)
      save_edit(participants, start_time: start_time, end_time: end_time, space_id: event_params[:space_id],
                              recurrence_rule: event_params[:recurrence_rule].presence)
    when "all"
      start_time, end_time = @event.times_after_update(@start_time, @end_time, keep: keep_dialog_times?, series: true)
      save_edit(participants, start_time: start_time, end_time: end_time,
                              recurrence_rule: series_rule.with_time_from(event_params[:recurrence_rule], at: start_time))
    when "this" then update_this_occurrence(participants)
    else dialog_done(alert: "Invalid update scope.")
    end
  end

  def delete_with_scope
    @event = Event.find(params[:id])
    return remove_event("Event deleted.") if @event.recurrence_rule.blank?

    case params[:scope]
    when "single" then shorten_event_series("This occurrence deleted.", :without_occurrence)
    when "following" then shorten_event_series("This and following deleted.", :ending_before)
    when "all" then remove_event("Event series deleted.")
    else dialog_done(alert: "Invalid delete scope: #{params[:scope]}")
    end
  rescue ActiveRecord::RecordInvalid => e
    # A series stored with a sub-daily rule no longer validates.
    dialog_done(alert: validation_message(e.record, "failed_saves.event_update"))
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    # Pre-load all staff space colors in ONE query
    staff_colors = StaffSpace.colors_in(params[:id])
    # Pre-load associations in ONE query; the events the window (CalendarWindow) keeps.
    event_sources = CalendarWindow.from_params(params).records(Event.where(space_id: params[:id]))
      .includes(:course_name, event_assignments: :user)
      .group_by(&:event_type)
      .map do |event_type, events|        
      {
        id: event_type,
        events: events.map do |event|
          # seconds to milliseconds because javascript
          duration = (event.end_time.to_time - event.start_time.to_time) * 1000

          rrule_data = helpers.date_formatted_recurrence_rule(event)

          background = if event.event_assignments.empty?
            "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);#{' opacity: 0.8;' if event.draft}"
          else
            total = event.event_assignments.size
            stops = event.event_assignments.map.with_index do |ea, i|
              c = staff_colors[ea.user_id] || '#bbb' # Fallback to '#bbb' if color is missing
              s = (100.0 / total) * i
              e = (100.0 / total) * (i + 1)
              "#{c} #{s}%, #{c} #{e}%"
            end.join(', ')

            "linear-gradient(to right, #{stops});#{' opacity: 0.8;' if event.draft}"
          end

          {
            id: "event-#{event.id}",
            title: event.display_title(include_draft_indicator: true),
            start: event.start_time.iso8601,
            end: event.end_time.iso8601,
            **(event.recurrence_rule.present? ? { rrule: rrule_data, duration: duration } : {}),
            allDay: CalendarTime.all_day?(event.start_time, event.end_time),
            extendedProps: {
              name: event.event_type.capitalize,
              draft: event.draft,
              description: event.description,
              eventType: event.event_type,
              trainingId: event.training_id,
              language: event.language,
              course_name: event.course_name,
              assignedUsers: if event.event_assignments.empty?
                [{id: 0, name: 'Unassigned'}]
              else
                event.event_assignments.map { |ea| { id: ea.user&.id, name: ea.user&.name } }
              end,
              background: background
            },
          }
        end
      }
    end

    render json: event_sources
  end

  def publish
    if params[:id].blank?
      space_id = params[:space_id]
      return redirect_back(fallback_location: admin_calendar_index_path, alert: "Space ID is required.") if space_id.blank?

      updated_count = 0
      failures = []

      Event.where(space_id: space_id, start_time: @view_start..@view_end, draft: true).find_each do |event|
        if event.update(draft: false, updated_by: current_user)
          event.push_to_google_later
          updated_count += 1
        else
          failures << "#{event.title.presence || "Event ##{event.id}"} (#{event.errors.full_messages.to_sentence})"
        end
      end

      flash[:alert] = "Failed to publish #{failures.size} event(s): #{failures.to_sentence}" if failures.any?
      return redirect_back(fallback_location: admin_calendar_index_path, notice: "#{updated_count} event(s) published.")
    else
      @event = Event.find(params[:id])
      if @event.update(draft: false, updated_by: current_user)
        @event.push_to_google_later
        dialog_done(notice: "Event published successfully.")
      else
        dialog_done(alert: validation_message(@event, "failed_saves.event_publish"))
      end
    end
  end

  def delete_drafts
    space_id = params[:space_id]
    return redirect_back(fallback_location: admin_calendar_index_path, alert: "Space ID is required.") if space_id.blank?

    draft_events = Event.where(space_id: space_id, start_time: @view_start..@view_end, draft: true, recurrence_rule: [nil, ""]).includes(:space).to_a
    draft_events.each { |event| destroy_event(event) }
    deleted_count = draft_events.size
        
    redirect_back(fallback_location: admin_calendar_index_path, 
      notice: "#{deleted_count} draft event(s) deleted. Any recurring events were untouched and must be deleted separately.")
  end

  def copy
    source_range = params[:source_range]&.split(" to ")
    target_date = params[:target_date]
    space_id = params[:space_id]

    if source_range.blank? || target_date.blank? || space_id.blank?
      return redirect_back(fallback_location: admin_calendar_index_path, alert: "Please fill out all fields before copying.")
    end

    dates = copy_dates(source_range, target_date)
    return redirect_back(fallback_location: admin_calendar_index_path, alert: I18n.t("errors.admin.events.copy_dates_invalid")) if dates.nil?

    start_date, end_date, new_start_date = dates
    copied_count = copy_published_events(space_id, start_date.beginning_of_day..end_date.end_of_day, new_start_date.beginning_of_day)
    redirect_back(fallback_location: admin_calendar_index_path,
      notice: "#{copied_count} published event(s) copied to #{new_start_date.to_date}. Recurring events were skipped.")
  rescue ActiveRecord::RecordInvalid => e
    # The copies are made in one transaction, so nothing was copied.
    redirect_back(fallback_location: admin_calendar_index_path, alert: validation_message(e.record, "errors.admin.events.copy_failed"))
  end

  private

  # Copies the published, non-recurring events of the space in the range to drafts starting on the new date;
  # returns how many were copied.
  def copy_published_events(space_id, range, new_start_date)
    events_to_copy = Event.where(space_id: space_id, start_time: range, draft: false, recurrence_rule: [nil, ""])
    copied_count = 0
    Event.transaction do
      events_to_copy.find_each do |event|
        copy_event_as_draft(event, range.begin, new_start_date)
        copied_count += 1
      end
    end
    copied_count
  end

  # The range start, range end and target date the user picked, or nil when one is not a date.
  def copy_dates(source_range, target_date)
    dates = [source_range[0], source_range[1], target_date].map { |value| parse_copy_date(value) }
    dates unless dates.any?(&:nil?)
  end

  def parse_copy_date(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # Parses the posted start and end times once; a missing or unparsable value answers with an alert.
  def parse_event_times
    @start_time = parse_time(event_params[:utc_start_time])
    @end_time = parse_time(event_params[:utc_end_time])
    return if @start_time && @end_time

    dialog_done(alert: t("admin_events.times_required"))
  end

  # delete_drafts, and publish when it publishes a whole range rather than one event
  def view_range_action?
    action_name == "delete_drafts" || (action_name == "publish" && params[:id].blank?)
  end

  def parse_view_range
    @view_start = parse_view_time(params[:view_start_date])
    @view_end = parse_view_time(params[:view_end_date])
    return if @view_start && @view_end

    redirect_back(fallback_location: admin_calendar_index_path, alert: t("admin_events.dates_required"))
  end

  # The calendar sends its view range as local times without an offset, so a value without one is
  # read in the app's time zone. Nil when the value is blank or not a time.
  def parse_view_time(value)
    Time.zone.parse(value.to_s)&.utc
  rescue ArgumentError
    nil
  end

  def series_rule
    RecurrenceRule.new(@event.recurrence_rule, @event.start_time)
  end

  # Excludes the occurrence from the series and creates it as its own event. Both happen in one
  # transaction, so a failure leaves the series as it was.
  def update_this_occurrence(participants)
    excluded, start_time, end_time = @event.occurrence_after_update(@start_time, @end_time, keep: keep_dialog_times?)
    updated_rule = series_rule.appending_exdate(excluded)

    # The replacement is checked before anything is saved: saving the series pushes to Google, which a
    # rollback cannot undo. A failure after this point (a database error) can still leave Google ahead.
    @new_event = Event.new(**dialog_fields, space_id: event_params[:space_id], start_time: start_time, end_time: end_time,
                           recurrence_rule: nil, created_by_id: current_user.id)
    raise ActiveRecord::RecordInvalid, @new_event unless @new_event.valid?

    series_updated = Event.transaction do
      next false unless @event.update(recurrence_rule: updated_rule, updated_by: current_user)

      @new_event.save!
      attach_participants(@new_event, participants)
      true
    end

    if series_updated
      @event.push_to_google_later
      @new_event.push_to_google_later
      dialog_done(notice: "This event occurrence updated successfully.")
    else
      dialog_done(alert: validation_message(@event, "failed_saves.event_update"))
    end
  end

  # Copies one event (and its assignments) as a draft on the matching day of the target week, at the same wall
  # clock time in the app's time zone.
  def copy_event_as_draft(event, start_date, new_start_date)
    days_offset = (event.start_time.to_date - start_date.to_date).to_i
    day = new_start_date + days_offset.days
    new_start = day.change(hour: event.start_time.hour, min: event.start_time.min,
                           sec: event.start_time.sec, usec: event.start_time.usec)
    new_end = event.end_time.present? ? (new_start + (event.end_time - event.start_time)) : nil

    new_event = event.dup
    new_event.start_time = new_start
    new_event.end_time = new_end
    new_event.draft = true
    new_event.google_event_id = nil
    new_event.google_calendar_id = nil
    new_event.updated_by = nil
    new_event.save!

    event.event_assignments.each do |assignment|
      new_event.event_assignments.create!(
        assignment.attributes.except("id", "event_id", "created_at", "updated_at")
      )
    end
  end

  def shorten_event_series(notice, change)
    @event.updated_by = current_user
    return dialog_done(alert: t("admin_events.start_date_required")) unless shorten_series(@event, change)

    @event.push_to_google_later
    dialog_done(notice: notice)
  end

  def remove_event(notice)
    destroy_event(@event)
    dialog_done(notice: notice)
  end

  # Destroys the event, then queues the removal of its Google copy (read before the row is gone).
  def destroy_event(event)
    google_event_id = event.google_event_id
    calendar_id = event.google_calendar
    Event.remove_from_google_later(google_event_id, calendar_id, event.id) if event.destroy
  end

  # Whether the dialog sent its time fields as it filled them from the clicked entry.
  def keep_dialog_times?
    params[:keep_series_times] == "1"
  end

  # The fields every save of the dialog writes; a blank title becomes the capitalized event type.
  def dialog_fields
    { title: event_params[:title].presence || event_params[:event_type].capitalize, description: event_params[:description],
      event_type: event_params[:event_type], training_id: event_params[:training_id], language: event_params[:language],
      course_name_id: event_params[:course_name] }
  end

  # Updates the event with the dialog's fields and `changes`, then replaces its staff and pushes it to Google.
  def save_edit(participants, **changes)
    if @event.update(**dialog_fields, **changes, updated_by: current_user)
      @event.event_assignments.destroy_all
      attach_participants(@event, participants)
      @event.push_to_google_later
      dialog_done(notice: "Event updated successfully.")
    else
      dialog_done(alert: validation_message(@event, "failed_saves.event_update"))
    end
  end

  def attach_participants(event, participants)
    return if participants.empty?

    event.event_assignments << participants.map { |staff_id| EventAssignment.new(event: event, user_id: staff_id) }
  end

  def event_params
    params.require(:event).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule, :event_type, :space_id, :training_id, :language, :course_name
    )
  end
end

