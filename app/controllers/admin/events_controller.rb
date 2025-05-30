class Admin::EventsController < AdminAreaController
  layout "admin_area"

  def create
    event_params = params.require(:event).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule, :event_type, :space_id
    )

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
      event_type: event_params[:event_type]
    )

    unless participants.empty?
      Rails.logger.info("Creating event assignments for participants: #{participants.inspect}")
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
    redirect_to admin_calendar_index_path
  end

  def update
    @event = Event.find(params[:id])

    event_params = params.require(:event).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule, :event_type, :space_id
    )

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
        event_type: event_params[:event_type]
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
      old_date_new_time_start = combine_date_and_time(@event.start_time.utc, 
Time.parse(event_params[:utc_start_time]).utc)
      duration = (Time.parse(event_params[:utc_end_time]).utc - Time.parse(event_params[:utc_start_time]).utc).to_i
      old_date_new_time_end = old_date_new_time_start + duration


      old_rrule, old_dtstart, old_extra_lines  = parse_rrule_and_dtstart(@event.recurrence_rule)
      new_rrule, new_dtstart, _new_extra_lines  = parse_rrule_and_dtstart(event_params[:recurrence_rule])

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
          event_type: event_params[:event_type],
          start_time: old_date_new_time_start,
          end_time: old_date_new_time_end,
          recurrence_rule: rule_to_use
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
      exclusion_start_time = combine_date_and_time(Time.parse(event_params[:utc_start_time]).utc, @event.start_time.utc)

      updated_rule = add_exdate_to_rrule(@event.recurrence_rule, exclusion_start_time)

      @event.update(recurrence_rule: updated_rule)

      Event.create!(
        title: title,
        description: event_params[:description],
        # the dates are already in utc but for consistent formatting with @event, we will do it explicitly
        start_time: Time.parse(event_params[:utc_start_time]).utc,
        end_time: Time.parse(event_params[:utc_end_time]).utc,
        recurrence_rule: nil,
        created_by_id: current_user.id,
        space_id: event_params[:space_id],
        event_type: event_params[:event_type]
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

      flash[:notice] = "This event occurrence updated successfully."
    end

    redirect_to admin_calendar_index_path
  end

  def delete_with_scope
    @event = Event.find(params[:id])
    scope = params[:scope]

    if @event.recurrence_rule.blank?
      # No recurrence: just delete it normally
      @event.destroy
      redirect_to admin_calendar_index_path, notice: "Event deleted."
      return
    end

    rrule_line, dtstart, rest_of_lines = parse_rrule_and_dtstart(@event.recurrence_rule)
    exdates = []

    case scope
    when "single"
      exdates << Time.parse(params[:start_date]).utc.strftime("%Y%m%dT%H%M%SZ")
    when "following"
      previous_day = Time.parse(params[:start_date]).utc - 24 * 60 * 60
      rrule_line = "#{remove_until_from_rrule(rrule_line)};UNTIL=#{previous_day.strftime("%Y%m%dT%H%M%SZ")}"
    when "all"
      @event.destroy
      redirect_to admin_calendar_index_path, notice: "Event series deleted."
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

    redirect_to admin_calendar_index_path, notice: "Event deleted (#{scope})."
  end

  def json
    return render json: { error: "Space ID is required" }, status: :bad_request if params[:id].blank?

    event_sources = Event.where(space_id: params[:id])
      .group_by(&:event_type)
      .map do |event_type, events|
      {
        id: event_type,
        # color: generate_color_from_id(event_type),
        events: events.map do |event|
          title = if event.title == event.event_type.capitalize && !event.event_assignments.empty?
            "#{event.event_type.capitalize} for #{event.event_assignments.map { |ea| ea.user.name }.join(", ")}"
          else 
            event.title
          end

          # seconds to milliseconds because javascript
          duration = (event.end_time.to_time - event.start_time.to_time) * 1000

          background = "linear-gradient(to right, #{event.event_assignments.map.with_index do |ea, i|
 c = helpers.generate_color_from_id(ea.user_id)
 s = (100.0 / event.event_assignments.size) * i
 e = (100.0 / event.event_assignments.size) * (i + 1)
 "#{c} #{s}%, #{c} #{e}%" end.join(', ')});#{' opacity: 0.6;' if event.draft}"


          {
            id: "event-#{event.id}",
            title: title,
            start: event.start_time.iso8601,
            end: event.end_time.iso8601,
            **(event.recurrence_rule.present? ? { rrule: event.recurrence_rule, duration: duration } : {}),
            allDay: event.start_time.to_time == event.end_time.to_time - 1.day,
            extendedProps: {
              name: event.event_type.capitalize,
              draft: event.draft,
              description: event.description,
              eventType: event.event_type,
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
    @event = Event.find(params[:id])
    if @event.update(draft: false)
      flash[:notice] = "Event published successfully."
    else
      flash[:alert] = "Failed to publish event: #{@event.errors.full_messages.to_sentence}"
    end
    redirect_to admin_calendar_index_path
  end

  private

  def parse_rrule_and_dtstart(rule_string)
    lines = rule_string.strip.split("\n")
    rrule_line = lines.find { |l| l.start_with?("RRULE:") }&.sub("RRULE:", "")
    dtstart_line = lines.find { |l| l.start_with?("DTSTART:") }&.sub("DTSTART:", "")

    rest_of_lines = lines.reject { |l| l.start_with?("RRULE:", "DTSTART:") }

    dtstart = dtstart_line.present? ? Time.parse(dtstart_line) : nil
    
    [rrule_line, dtstart, rest_of_lines]
  end

  def add_exdate_to_rrule(rrule_str, date_to_exclude)
    return rrule_str if rrule_str.blank? || date_to_exclude.blank?

    exdate = date_to_exclude.strftime('%Y%m%dT%H%M%SZ')
    "#{rrule_str}\nEXDATE:#{exdate}"
  end

  def combine_date_and_time(keep_date, keep_time)
    keep_date.change(
      hour: keep_time.hour,
      min: keep_time.min,
      sec: keep_time.sec
    )
  end

  def remove_until_from_rrule(rrule_line)
    rrule_line = rrule_line.gsub(/;UNTIL=[^;Z]*Z/, '') if rrule_line.include?('UNTIL=')
    rrule_line
  end
end