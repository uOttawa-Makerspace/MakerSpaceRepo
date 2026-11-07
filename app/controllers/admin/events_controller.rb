class Admin::EventsController < AdminAreaController
  layout "admin_area"

  before_action :require_event_times, only: %i[create update]
  before_action :require_view_dates, if: :view_range_action?

  def create
    participants = params[:staff_select].presence || []

    title = if event_params[:title].blank? || event_params[:title].strip.empty?
      event_params[:event_type].capitalize
    else 
      event_params[:title]
    end 

    @event = Event.new(
      title: title,
      description: event_params[:description],
      # the dates are already in utc but for consistent formatting with @event, we will do it explicitly
      start_time: Time.parse(event_params[:utc_start_time]).utc,
      end_time: Time.parse(event_params[:utc_end_time]).utc,
      recurrence_rule: event_params[:recurrence_rule].presence,
      created_by_id: current_user.id,
      space_id: event_params[:space_id],
      event_type: event_params[:event_type],
      training_id: event_params[:training_id],
      language: event_params[:language],
      course_name_id: event_params[:course_name]
    )

    unless participants.empty?
      @event_assignments = participants.map do |staff_id|
        EventAssignment.new(
          event: @event,
          user_id: staff_id
        )
      end
    end

    saved = @event.save && Array(@event_assignments).all?(&:save)
    @event.push_to_google_later if @event.persisted?

    if saved
      flash[:notice] = "Event created successfully."
    else
      flash[:alert] = "Failed to create event: #{@event.errors.full_messages.to_sentence}"
    end
    redirect_back(fallback_location: admin_calendar_index_path)
  end

  def update
    @event = Event.find(params[:id])

    participants = params[:staff_select].presence || []

    title = if event_params[:title].blank? || event_params[:title].strip.empty?
      event_params[:event_type].capitalize
    else 
      event_params[:title]
    end 

    update_scope = if @event.recurrence_rule.present?
      params[:update_scope]
    else
      "non-recurring"
    end

    case update_scope
    when "non-recurring"
      if @event.update(
        title: title,
        description: event_params[:description],
        # the dates are already in utc but for consistent formatting with @event, we will do it explicitly
        start_time: Time.parse(event_params[:utc_start_time]).utc,
        end_time: Time.parse(event_params[:utc_end_time]).utc,
        recurrence_rule: event_params[:recurrence_rule].presence,
        created_by_id: current_user.id,
        space_id: event_params[:space_id],
        event_type: event_params[:event_type],
        training_id: event_params[:training_id],
        language: event_params[:language],
        course_name_id: event_params[:course_name]
        )

        # Update event assignments
        @event.event_assignments.destroy_all
        unless participants.empty?
          @event_assignments = participants.map do |staff_id|
            EventAssignment.new(
              event: @event,
              user_id: staff_id
            )
          end
          @event.event_assignments << @event_assignments
        end

        @event.push_to_google_later

        flash[:notice] = "Event updated successfully."
      else
        flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
      end
    when "all"
      old_date_new_time_start = helpers.combine_date_and_time(
        @event.start_time.utc, 
        Time.parse(event_params[:utc_start_time]).utc
      )
      duration = (Time.parse(event_params[:utc_end_time]).utc - Time.parse(event_params[:utc_start_time]).utc).to_i
      old_date_new_time_end = old_date_new_time_start + duration

      old_rrule, old_dtstart, old_extra_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)
      new_rrule, new_dtstart, _new_extra_lines = helpers.parse_rrule_and_dtstart(event_params[:recurrence_rule])

      rule_to_use = if old_rrule == new_rrule && old_dtstart && new_dtstart
        combined_dtstart = old_dtstart.change(
          hour: new_dtstart.hour,
          min: new_dtstart.min,
          sec: new_dtstart.sec
        )
        
        ([
          "DTSTART:#{combined_dtstart.strftime('%Y%m%dT%H%M%SZ')}",
          "RRULE:#{old_rrule}"
        ] + old_extra_lines).join("\n")
      else
        # the freq changed so we don't care if the dtstart is the new date
        event_params[:recurrence_rule]
      end

      if @event.update(
          title: title,
          description: event_params[:description],
          start_time: old_date_new_time_start,
          end_time: old_date_new_time_end,
          recurrence_rule: rule_to_use,
          event_type: event_params[:event_type],
          training_id: event_params[:training_id],
          language: event_params[:language],
          course_name_id: event_params[:course_name]
          )

        # Update event assignments
        @event.event_assignments.destroy_all
        unless participants.empty?
          @event_assignments = participants.map do |staff_id|
            EventAssignment.new(
              event: @event,
              user_id: staff_id
            )
          end
          @event.event_assignments << @event_assignments
        end

        @event.push_to_google_later

        flash[:notice] = "Unavailability updated successfully."
      else
        flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
      end
    when "this"
      update_this_occurrence(title, participants)
    else
      flash[:alert] = "Invalid update scope."
    end

    redirect_back(fallback_location: admin_calendar_index_path)
  end

  def delete_with_scope
    @event = Event.find(params[:id])
    scope = params[:scope]

    if @event.recurrence_rule.blank?
      # No recurrence: just delete it normally
      destroy_event(@event)
      redirect_back(fallback_location: admin_calendar_index_path, notice: "Event deleted.")
      return
    end

    case scope
    when "single"
      if params[:start_date].blank?
        return redirect_back(fallback_location: admin_calendar_index_path, alert: "Start date is required.")
      end
      
      rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)
      exdate = Time.parse(params[:start_date]).utc.strftime("%Y%m%dT%H%M%SZ")
      
      rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @event.start_time)
      recurrence_lines = [
        "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}",
        "RRULE:#{rule}",
        "EXDATE:#{exdate}"
      ]
      
      @event.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))
      @event.push_to_google_later
      redirect_back(fallback_location: admin_calendar_index_path, notice: "This occurrence deleted.")
      
    when "following"
      if params[:start_date].blank?
        return redirect_back(fallback_location: admin_calendar_index_path, alert: "Start date is required.")
      end
      
      rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)
      previous_day = Time.parse(params[:start_date]).utc - 24.hours
      rrule_line = "#{helpers.remove_until_from_rrule(rrule_line)};UNTIL=#{previous_day.strftime("%Y%m%dT%H%M%SZ")}"
      
      rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @event.start_time)
      recurrence_lines = [
        "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}",
        "RRULE:#{rule}"
      ]
      
      @event.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))
      @event.push_to_google_later
      redirect_back(fallback_location: admin_calendar_index_path, notice: "This and following deleted.")
      
    when "all"
      destroy_event(@event)
      redirect_back(fallback_location: admin_calendar_index_path, notice: "Event series deleted.")
      
    else
      redirect_back(fallback_location: admin_calendar_index_path, alert: "Invalid delete scope: #{scope}")
    end
  rescue ActiveRecord::RecordInvalid => e
    # A series stored with a sub-daily rule no longer validates.
    redirect_back(fallback_location: admin_calendar_index_path, alert: "Failed to update event: #{e.record.errors.full_messages.to_sentence}")
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    # Pre-load all staff space colors in ONE query
    staff_colors = StaffSpace.where(space_id: params[:id]).pluck(:user_id, :color).to_h

    # Pre-load associations in ONE query
    event_sources = Event.where(space_id: params[:id])
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
      start_date = Time.parse(params[:view_start_date]).utc
      end_date = Time.parse(params[:view_end_date]).utc
      space_id = params[:space_id]
      return redirect_back(fallback_location: admin_calendar_index_path, alert: "Space ID is required.") if space_id.blank?

      updated_count = 0
      failures = []

      Event.where(space_id: space_id, start_time: start_date..end_date, draft: true).find_each do |event|
        if event.update(draft: false)
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
      if @event.update(draft: false)
        @event.push_to_google_later
        flash[:notice] = "Event published successfully."
      else
        flash[:alert] = "Failed to publish event: #{@event.errors.full_messages.to_sentence}"
      end
    end

    redirect_back(fallback_location: admin_calendar_index_path)
  end

  def delete_drafts
    start_date = Time.parse(params[:view_start_date]).utc
    end_date = Time.parse(params[:view_end_date]).utc
    space_id = params[:space_id]
    return redirect_back(fallback_location: admin_calendar_index_path, alert: "Space ID is required.") if space_id.blank?

    draft_events = Event.where(space_id: space_id, start_time: start_date..end_date, draft: true, recurrence_rule: [nil, ""]).includes(:space).to_a
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

    begin
      start_date = Time.zone.parse(source_range[0]).beginning_of_day
      end_date = Time.zone.parse(source_range[1]).end_of_day
      new_start_date = Time.zone.parse(target_date).beginning_of_day

      # Find events in range
      events_to_copy = Event.where(
        space_id: space_id,
        start_time: start_date..end_date,
        draft: false,
        recurrence_rule: [nil, ""]
      )

      copied_count = 0

      Event.transaction do
        events_to_copy.find_each do |event|
          copy_event_as_draft(event, start_date, new_start_date)
          copied_count += 1
        end
      end

      redirect_back(fallback_location: admin_calendar_index_path,
        notice: "#{copied_count} published event(s) copied to #{new_start_date.to_date}. Recurring events were skipped.")
    rescue StandardError => e
      redirect_back(fallback_location: admin_calendar_index_path, alert: "Error copying events: #{e.message}")
    end
  end

  private

  def require_event_times
    return if event_params.values_at(:utc_start_time, :utc_end_time).all?(&:present?)

    redirect_back(fallback_location: admin_calendar_index_path, alert: "Start and end times are required.")
  end

  # delete_drafts, and publish when it publishes a whole range rather than one event
  def view_range_action?
    action_name == "delete_drafts" || (action_name == "publish" && params[:id].blank?)
  end

  def require_view_dates
    return if params.values_at(:view_start_date, :view_end_date).all?(&:present?)

    redirect_back(fallback_location: admin_calendar_index_path, alert: "Start and end dates are required.")
  end

  # Excludes the occurrence from the series and creates it as its own event. Both happen in one
  # transaction, so a failure leaves the series as it was.
  def update_this_occurrence(title, participants)
    exclusion_start_time = helpers.combine_date_and_time(
      Time.parse(event_params[:utc_start_time]).utc,
      @event.start_time.utc
    )
    updated_rule = helpers.add_exdate_to_rrule(@event.recurrence_rule, exclusion_start_time)

    # The replacement is checked before anything is saved: saving the series pushes to Google, which a
    # rollback cannot undo. A failure after this point (a database error) can still leave Google ahead.
    @new_event = build_occurrence_event(title)
    raise ActiveRecord::RecordInvalid, @new_event unless @new_event.valid?

    series_updated = Event.transaction do
      next false unless @event.update(recurrence_rule: updated_rule)

      @new_event.save!
      attach_participants(@new_event, participants)
      true
    end

    if series_updated
      @event.push_to_google_later
      @new_event.push_to_google_later
      flash[:notice] = "This event occurrence updated successfully."
    else
      flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
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
    new_event.save!

    event.event_assignments.each do |assignment|
      new_event.event_assignments.create!(
        assignment.attributes.except("id", "event_id", "created_at", "updated_at")
      )
    end
  end

  # Destroys the event, then queues the removal of its Google copy (read before the row is gone).
  def destroy_event(event)
    google_event_id = event.google_event_id
    calendar_id = event.google_calendar
    Event.remove_from_google_later(google_event_id, calendar_id, event.id) if event.destroy
  end

  def build_occurrence_event(title)
    Event.new(
      title: title,
      description: event_params[:description],
      # the dates are already in utc but for consistent formatting with @event, we will do it explicitly
      start_time: Time.parse(event_params[:utc_start_time]).utc,
      end_time: Time.parse(event_params[:utc_end_time]).utc,
      recurrence_rule: nil,
      created_by_id: current_user.id,
      space_id: event_params[:space_id],
      event_type: event_params[:event_type],
      training_id: event_params[:training_id],
      language: event_params[:language],
      course_name_id: event_params[:course_name]
    )
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

