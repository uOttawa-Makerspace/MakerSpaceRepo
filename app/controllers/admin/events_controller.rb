class Admin::EventsController < AdminAreaController
  layout "admin_area"

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
      recurrence_rule: event_params[:recurrence_rule],
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

    if @event.save && Array(@event_assignments).all?(&:save)
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
        recurrence_rule: event_params[:recurrence_rule],
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
        
        flash[:notice] = "Event updated successfully."
      else
        flash[:alert] = "Failed to update event: #{@event.errors.full_messages.to_sentence}"
      end
    when "all"
      old_date_new_time_start = helpers.combine_date_and_time(@event.start_time.utc, 
Time.parse(event_params[:utc_start_time]).utc)
      duration = (Time.parse(event_params[:utc_end_time]).utc - Time.parse(event_params[:utc_start_time]).utc).to_i
      old_date_new_time_end = old_date_new_time_start + duration


      old_rrule, old_dtstart, old_extra_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)
      new_rrule, new_dtstart, _new_extra_lines = helpers.parse_rrule_and_dtstart(event_params[:recurrence_rule])

      rule_to_use = if old_rrule == new_rrule
        # the freq is the same, so we just need to make the dtstart time correct
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

        flash[:notice] = "Unavailability updated successfully."
      else
        flash[:alert] = "Failed to update unavailability: #{@event.errors.full_messages.to_sentence}"
      end
    when "this"
      exclusion_start_time = helpers.combine_date_and_time(Time.parse(event_params[:utc_start_time]).utc, 
@event.start_time.utc)

      updated_rule = helpers.add_exdate_to_rrule(@event.recurrence_rule, exclusion_start_time)

      @event.update(recurrence_rule: updated_rule)

      @new_event = Event.create!(
        title: title,
        description: event_params[:description],
        # the dates are already in utc but for consistent formatting with @event, we will do it explicitly
        start_time: Time.parse(event_params[:utc_start_time]).utc,
        end_time: Time.parse(event_params[:utc_end_time]).utc,
        recurrence_rule: '',
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
          EventAssignment.new(
            event: @new_event,
            user_id: staff_id
          )
        end
        @new_event.event_assignments << @event_assignments
      end 

      flash[:notice] = "This event occurrence updated successfully."
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

    rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@event.recurrence_rule)
    exdates = []

    case scope
    when "single"
      exdates << Time.parse(params[:start_date]).utc.strftime("%Y%m%dT%H%M%SZ")
    when "following"
      previous_day = Time.parse(params[:start_date]).utc - 24 * 60 * 60
      rrule_line = "#{helpers.remove_until_from_rrule(rrule_line)};UNTIL=#{previous_day.strftime("%Y%m%dT%H%M%SZ")}"
    when "all"
      @event.destroy
      redirect_back(fallback_location: admin_calendar_index_path, notice: "Event series deleted.")
      return

    else
      head :bad_request
      return
    end

    rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @event.start_time)
    recurrence_lines = []
    recurrence_lines << "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}"
    recurrence_lines << "RRULE:#{rule}"
    exdates.each do |ex|
      recurrence_lines << "EXDATE:#{ex}"
    end

    @event.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))

    redirect_back(fallback_location: admin_calendar_index_path, notice: "Event deleted (#{scope}).")
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
            "#{if event.draft
                 '✎ '
               end}#{event.event_type == 'training' ? "#{event.training.name} (#{event.course_name.name || ''} - #{event.language || ''})" : event.event_type.capitalize} for #{event.event_assignments.map do |ea|
 ea.user.name end.join(", ")}"
          else 
            "#{'✎ ' if event.draft}#{event.title}"
          end

          # seconds to milliseconds because javascript
          duration = (event.end_time.to_time - event.start_time.to_time) * 1000

          rrule_data = if event.recurrence_rule.present?
            rrule = event.recurrence_rule          
            rrule_parts = rrule.split(/[;\n]/).reject { |part| part.strip.start_with?('DTSTART') }
            rrule_without_dtstart = rrule_parts.join(';').gsub(/;EXDATE/, "\nEXDATE")
            dtstart_toronto = event.start_time.in_time_zone("America/Toronto")&.strftime("%Y%m%dT%H%M%S")          
            "DTSTART:#{dtstart_toronto}\n#{rrule_without_dtstart}"
          end

          background = "linear-gradient(to right, #{event.event_assignments.map.with_index do |ea, i|
 c = StaffSpace.find_by(user_id: ea.user_id, space_id: params[:id])&.color
 s = (100.0 / event.event_assignments.size) * i
 e = (100.0 / event.event_assignments.size) * (i + 1)
 "#{c} #{s}%, #{c} #{e}%" end.join(', ')});#{' opacity: 0.8;' if event.draft}"


          {
            id: "event-#{event.id}",
            title: title,
            start: event.start_time.iso8601,
            end: event.end_time.iso8601,
            **(event.recurrence_rule.present? ? { rrule: rrule_data, duration: duration } : {}),
            allDay: event.start_time.to_time == event.end_time.to_time - 1.day,
            extendedProps: {
              name: event.event_type.capitalize,
              draft: event.draft,
              description: event.description,
              eventType: event.event_type,
              trainingId: event.training_id,
              language: event.language,
              course_name: event.course_name, # not just the id... pass the object
              assignedUsers: event.event_assignments.map { |ea| { id: ea.user.id, name: ea.user.name } },
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
      return if space_id.empty?

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
    return if space_id.empty?

    draft_events = Event.where(space_id: space_id, start_time: start_date..end_date, draft: true, 
recurrence_rule: [nil, ""])
    deleted_count = draft_events.destroy_all.size
        
    redirect_back(fallback_location: admin_calendar_index_path, 
notice: "#{deleted_count} draft event(s) deleted. Any recurring events were untouched and must be deleted separately.")
  end

  def copy
    source_range = params[:source_range]&.split(" to ")
    target_date = params[:target_date]
    space_id = params[:space_id]

    if source_range.blank? || target_date.blank? || space_id.blank?
      return redirect_back(fallback_location: admin_calendar_index_path, 
alert: "Please fill out all fields before copying.")
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

      events_to_copy.find_each do |event|
        days_offset = (event.start_time.to_date - start_date.to_date).to_i
        event_offset = event.start_time - event.start_time.beginning_of_day
        new_start = new_start_date + days_offset.days + event_offset
        new_end = event.end_time.present? ? (new_start + (event.end_time - event.start_time)) : nil

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
