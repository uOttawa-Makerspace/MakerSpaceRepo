class Staff::UnavailabilitiesController < StaffAreaController
  layout "staff_area"

  def create
    staff_params = params.require(:staff_unavailability).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule
    )

    title = if staff_params[:title].blank? || staff_params[:title].strip.empty?
      "Unavailable"
    else 
      staff_params[:title]
    end 

    @staff_unavailability = StaffUnavailability.new(
      title: title,
      description: ActionController::Base.helpers.strip_tags(staff_params[:description]),
      # the dates are already in utc but for consistent formatting with @staff_unavailability, we will do it explicitly
      start_time: Time.parse(staff_params[:utc_start_time]).utc,
      end_time: Time.parse(staff_params[:utc_end_time]).utc,
      recurrence_rule: staff_params[:recurrence_rule],
      user_id: current_user.id
    )

    if @staff_unavailability.save
      flash[:notice] = "Unavailability created successfully."
    else
      flash[:alert] = "Failed to create unavailability: #{@staff_unavailability.errors.full_messages.to_sentence}"
    end
    redirect_to staff_unavailabilities_path
  end

  def update
    @staff_unavailability = StaffUnavailability.find(params[:id])

    staff_params = params.require(:staff_unavailability).permit(
      :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule
    )

    update_scope = if @staff_unavailability.recurrence_rule.present?
      params[:update_scope]
    else
      "non-recurring"
    end

    case update_scope
    when "non-recurring"
      if @staff_unavailability.update(
          title: staff_params[:title] || "Unavailable",
          description: ActionController::Base.helpers.strip_tags(staff_params[:description]),
          start_time: staff_params[:utc_start_time],
          end_time: staff_params[:utc_end_time],
          recurrence_rule: staff_params[:recurrence_rule]
        )
        flash[:notice] = "Unavailability updated successfully."
      else
        flash[:alert] = "Failed to update unavailability: #{@staff_unavailability.errors.full_messages.to_sentence}"
      end
    when "all"
      old_date_new_time_start = helpers.combine_date_and_time(@staff_unavailability.start_time.utc, 
Time.parse(staff_params[:utc_start_time]).utc)
      duration = (Time.parse(staff_params[:utc_end_time]).utc - Time.parse(staff_params[:utc_start_time]).utc).to_i
      old_date_new_time_end = old_date_new_time_start + duration


      old_rrule, old_dtstart, old_extra_lines = helpers.parse_rrule_and_dtstart(@staff_unavailability.recurrence_rule)
      new_rrule, new_dtstart, _new_extra_lines = helpers.parse_rrule_and_dtstart(staff_params[:recurrence_rule])

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
        staff_params[:recurrence_rule]
      end

      if @staff_unavailability.update(
          title: staff_params[:title] || "Unavailable",
          description: staff_params[:description],
          start_time: old_date_new_time_start,
          end_time: old_date_new_time_end,
          recurrence_rule: rule_to_use
        )
        flash[:notice] = "Unavailability updated successfully."
      else
        flash[:alert] = "Failed to update unavailability: #{@staff_unavailability.errors.full_messages.to_sentence}"
      end
    when "this"
      exclusion_start_time = helpers.combine_date_and_time(Time.parse(staff_params[:utc_start_time]).utc, 
@staff_unavailability.start_time.utc)

      updated_rule = helpers.add_exdate_to_rrule(@staff_unavailability.recurrence_rule, exclusion_start_time)

      @staff_unavailability.update(recurrence_rule: updated_rule)

      StaffUnavailability.create!(
        title: staff_params[:title] || "Unavailable",
        description: staff_params[:description],
        start_time: staff_params[:utc_start_time],
        end_time: staff_params[:utc_end_time],
        recurrence_rule: nil,
        user_id: current_user.id
      )

      flash[:notice] = "This occurrence updated successfully."
    end

    redirect_to staff_unavailabilities_path
  end

  def delete_with_scope
    @unavailability = StaffUnavailability.find(params[:id])
    scope = params[:scope]

    if @unavailability.recurrence_rule.blank?
      # No recurrence: just delete it normally
      @unavailability.destroy
      redirect_to staff_unavailabilities_path, notice: "Unavailability deleted."
      return
    end

    rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@unavailability.recurrence_rule)
    exdates = []

    case scope
    when "single"
      exdates << Time.parse(params[:start_date]).utc.strftime("%Y%m%dT%H%M%SZ")
    when "following"
      previous_day = Time.parse(params[:start_date]).utc - 24 * 60 * 60
      rrule_line = "#{helpers.remove_until_from_rrule(rrule_line)};UNTIL=#{previous_day.strftime("%Y%m%dT%H%M%SZ")}"
    when "all"
      @unavailability.destroy
      redirect_to staff_unavailabilities_path, notice: "Unavailability series deleted."
      return

    else
      head :bad_request
      return
    end

    rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @unavailability.start_time)
    recurrence_lines = []
    recurrence_lines << "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}"
    recurrence_lines << "RRULE:#{rule}"
    exdates.each do |ex|
      recurrence_lines << "EXDATE:#{ex}"
    end

    @unavailability.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))

    redirect_to staff_unavailabilities_path, notice: "Unavailability deleted (#{scope})."
  end

  def json
    @unavailabilities = StaffUnavailability.where(user_id: current_user.id)

    
    render json: @unavailabilities.map { |u| 
    duration = (u.end_time.to_time - u.start_time.to_time) * 1000
      {
        id: u.id,
        title: u.title || "Unavailable",
        start: u.start_time.iso8601,
        end: u.end_time.iso8601,
        **(u.recurrence_rule.present? ? { rrule: u.recurrence_rule, duration: duration } : {}),
        allDay: u.start_time.to_time == u.end_time.to_time - 1.day,
        extendedProps: {
          description: u.description
        }
      }
    }
  end
end