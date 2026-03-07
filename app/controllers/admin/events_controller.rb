class Admin::EventsController < AdminAreaController
  layout "admin_area"

  CALENDAR_TZ = ActiveSupport::TimeZone["America/Toronto"]

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
        EventAssignment.new(event: @event, user_id: staff_id)
      end
    end

    if @event.save && Array(@event_assignments).all?(&:save)
      @event.reload
      Event.upsert_event(@event) unless @event.draft
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
            EventAssignment.new(event: @event, user_id: staff_id)
          end
          @event.event_assignments << @event_assignments
        end

        @event.reload
        Event.upsert_event(@event) unless @event.draft
        flash[:notice] = "Event updated successfully."
      else
        flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
      end

    when "all"
      new_start_utc = Time.parse(event_params[:utc_start_time]).utc
      new_end_utc = Time.parse(event_params[:utc_end_time]).utc

      # Preserve wall-clock time, not UTC seconds
      new_start_local = new_start_utc.in_time_zone(CALENDAR_TZ)
      new_end_local = new_end_utc.in_time_zone(CALENDAR_TZ)
      original_local = @event.start_time.in_time_zone(CALENDAR_TZ)
      original_end_local = @event.end_time.in_time_zone(CALENDAR_TZ)

      # Keep the original date, apply the new wall-clock time
      old_date_new_time_start = CALENDAR_TZ.local(
        original_local.year, original_local.month, original_local.day,
        new_start_local.hour, new_start_local.min, new_start_local.sec
      )

      end_day_offset = (new_end_local.to_date - new_start_local.to_date).to_i
      end_target_date = old_date_new_time_start.to_date + end_day_offset
      old_date_new_time_end = CALENDAR_TZ.local(
        end_target_date.year, end_target_date.month, end_target_date.day,
        new_end_local.hour, new_end_local.min, new_end_local.sec
      )

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
            EventAssignment.new(event: @event, user_id: staff_id)
          end
          @event.event_assignments << @event_assignments
        end

        @event.reload
        Event.upsert_event(@event) unless @event.draft
        flash[:notice] = "Unavailability updated successfully."
      else
        flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
      end

    when "this"
      exclusion_start_time = helpers.combine_date_and_time(
        Time.parse(event_params[:utc_start_time]).utc,
        @event.start_time.utc
      )

      updated_rule = helpers.add_exdate_to_rrule(@event.recurrence_rule, exclusion_start_time)
      @event.update(recurrence_rule: updated_rule)

      @new_event = Event.create!(
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

      # Update event assignments
      unless participants.empty?
        @event_assignments = participants.map do |staff_id|
          EventAssignment.new(event: @new_event, user_id: staff_id)
        end
        @new_event.event_assignments << @event_assignments
      end

      @new_event.reload
      Event.upsert_event(@new_event) unless @new_event.draft
      flash[:notice] = "This event occurrence updated successfully."
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
      @event.destroy
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
      redirect_back(fallback_location: admin_calendar_index_path, notice: "This occurrence deleted.")

    when "following"
      if params[:start_date].blank?
        return redirect_back(fallback_location: admin_calendar_index_path, alert: "Start date is required.")
      end

      rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)

      # Compute UNTIL as "previous day, same wall-clock time" in calendar timezone
      clicked_local = Time.parse(params[:start_date]).in_time_zone(CALENDAR_TZ)
      prev_date = clicked_local.to_date - 1
      previous_occurrence = CALENDAR_TZ.local(
        prev_date.year, prev_date.month, prev_date.day,
        clicked_local.hour, clicked_local.min, clicked_local.sec
      )

      rrule_line = "#{helpers.remove_until_from_rrule(rrule_line)};UNTIL=#{previous_occurrence.utc.strftime("%Y%m%dT%H%M%SZ")}"

      rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @event.start_time)
      recurrence_lines = [
        "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}",
        "RRULE:#{rule}"
      ]

      @event.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))
      redirect_back(fallback_location: admin_calendar_index_path, notice: "This and following deleted.")

    when "all"
      @event.destroy
      redirect_back(fallback_location: admin_calendar_index_path, notice: "Event series deleted.")

    else
      redirect_back(fallback_location: admin_calendar_index_path, alert: "Invalid delete scope: #{scope}")
    end
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    event_sources = Event.where(space_id: params[:id])
      .group_by(&:event_type)
      .map do |event_type, events|
      {
        id: event_type,
        events: events.map do |event|
          title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
            "#{if event.draft then '✎ ' end}#{event.event_type == 'training' ? "#{event.training.name} (#{event.course_name&.name || ''} - #{event.language || ''})" : event.event_type.capitalize} for #{event.event_assignments.map { |ea| ea.user.name }.join(", ")}"
          else
            "#{'✎ ' if event.draft}#{event.title}"
          end

          # seconds to milliseconds because javascript
          duration = (event.end_time.to_time - event.start_time.to_time) * 1000

          rrule_data = helpers.date_formatted_recurrence_rule(event)

          background = if event.event_assignments.empty?
            "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);#{' opacity: 0.8;' if event.draft}"
          else
            "linear-gradient(to right, #{event.event_assignments.map.with_index do |ea, i|
              c = StaffSpace.find_by(user_id: ea.user_id, space_id: params[:id])&.color
              s = (100.0 / event.event_assignments.size) * i
              e = (100.0 / event.event_assignments.size) * (i + 1)
              "#{c} #{s}%, #{c} #{e}%"
            end.join(', ')});#{' opacity: 0.8;' if event.draft}"
          end

          # DST-safe all-day detection using wall-clock components
          start_local = event.start_time.in_time_zone(CALENDAR_TZ)
          end_local = event.end_time.in_time_zone(CALENDAR_TZ)
          is_all_day = start_local.hour == 0 && start_local.min == 0 && start_local.sec == 0 &&
                       end_local.hour == 0 && end_local.min == 0 && end_local.sec == 0 &&
                       end_local.to_date > start_local.to_date

          {
            id: "event-#{event.id}",
            title: title,
            start: event.start_time.iso8601,
            end: event.end_time.iso8601,
            **(event.recurrence_rule.present? ? { rrule: rrule_data, duration: duration } : {}),
            allDay: is_all_day,
            extendedProps: {
              name: event.event_type.capitalize,
              draft: event.draft,
              description: event.description,
              eventType: event.event_type,
              trainingId: event.training_id,
              language: event.language,
              course_name: event.course_name,
              assignedUsers: if event.event_assignments.empty?
                [{ id: 0, name: 'Unassigned' }]
              else
                event.event_assignments.map { |ea| { id: ea.user.id, name: ea.user.name } }
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
      Event.where(space_id: space_id, start_time: start_date..end_date, draft: true).find_each do |event|
        updated_count += 1 if event.update(draft: false)
      end

      return redirect_back(fallback_location: admin_calendar_index_path, notice: "#{updated_count} event(s) published.")
    else
      @event = Event.find(params[:id])
      if @event.update(draft: false)
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

    draft_events = Event.where(space_id: space_id, start_time: start_date..end_date, draft: true, recurrence_rule: [nil, ""])
    deleted_count = draft_events.destroy_all.size

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
      start_date = CALENDAR_TZ.parse(source_range[0]).beginning_of_day
      end_date = CALENDAR_TZ.parse(source_range[1]).end_of_day
      new_start_date = CALENDAR_TZ.parse(target_date).beginning_of_day

      # Find events in range
      events_to_copy = Event.where(
        space_id: space_id,
        start_time: start_date..end_date,
        draft: false,
        recurrence_rule: [nil, ""]
      )

      copied_count = 0

      events_to_copy.find_each do |event|
        # Work in wall-clock time to preserve local hours across DST
        source_start = event.start_time.in_time_zone(CALENDAR_TZ)
        source_end = event.end_time.in_time_zone(CALENDAR_TZ)

        days_offset = (source_start.to_date - start_date.to_date).to_i
        target_day = new_start_date.to_date + days_offset

        # Build new times from wall-clock components — DST-safe
        new_start = CALENDAR_TZ.local(
          target_day.year, target_day.month, target_day.day,
          source_start.hour, source_start.min, source_start.sec
        )

        end_day_offset = (source_end.to_date - source_start.to_date).to_i
        new_end_day = target_day + end_day_offset
        new_end = CALENDAR_TZ.local(
          new_end_day.year, new_end_day.month, new_end_day.day,
          source_end.hour, source_end.min, source_end.sec
        )

        new_event = event.dup
        new_event.start_time = new_start
        new_event.end_time = new_end
        new_event.draft = true
        new_event.google_event_id = ""
        new_event.save!

        copied_count += 1

        event.event_assignments.each do |assignment|
          new_event.event_assignments.create!(
            assignment.attributes.except("id", "event_id", "created_at", "updated_at")
          )
        end
      end

      redirect_back(fallback_location: admin_calendar_index_path,
        notice: "#{copied_count} published event(s) copied to #{new_start_date.to_date}. Recurring events were skipped.")
    rescue StandardError => e
      redirect_back(fallback_location: admin_calendar_index_path, alert: "Error copying events: #{e.message}")
    end
  end

  private

  def event_params
    params.require(:event).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule, :event_type, :space_id, :training_id, :language, :course_name
    )
  end
end