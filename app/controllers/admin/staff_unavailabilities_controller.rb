# app/controllers/admin/staff_unavailabilities_controller.rb
class Admin::StaffUnavailabilitiesController < AdminController
  def create
    user = User.find(unavailability_params[:user_id])
    
    title = unavailability_params[:title].presence || "Unavailable (Admin)"

    @staff_unavailability = StaffUnavailability.new(
      title: title,
      description: ActionController::Base.helpers.strip_tags(unavailability_params[:description].to_s),
      start_time: Time.parse(unavailability_params[:utc_start_time]).utc,
      end_time: Time.parse(unavailability_params[:utc_end_time]).utc,
      recurrence_rule: unavailability_params[:recurrence_rule].presence,
      user_id: user.id
    )

    if @staff_unavailability.save
      flash[:notice] = "Unavailability created for #{user.name}."
    else
      flash[:alert] = "Failed: #{@staff_unavailability.errors.full_messages.to_sentence}"
    end
    
    redirect_back fallback_location: admin_calendar_index_path
  end

  def update
    @staff_unavailability = StaffUnavailability.find(params[:id])
    update_scope = @staff_unavailability.recurrence_rule.present? ? params[:update_scope] : "non-recurring"

    case update_scope
    when "non-recurring"
      update_single_unavailability
    when "all"
      update_all_occurrences
    when "this"
      update_this_occurrence
    end

    redirect_back fallback_location: admin_calendar_index_path
  end

  def destroy
    @unavailability = StaffUnavailability.find(params[:id])
    @unavailability.destroy
    redirect_back fallback_location: admin_calendar_index_path, notice: "Unavailability deleted."
  end

  def delete_with_scope
    @unavailability = StaffUnavailability.find(params[:id])
    scope = params[:scope]

    if @unavailability.recurrence_rule.blank?
      @unavailability.destroy
      return redirect_back fallback_location: admin_calendar_index_path, notice: "Unavailability deleted."
    end

    case scope
    when "single"
      delete_single_occurrence
    when "following"
      delete_following_occurrences
    when "all"
      @unavailability.destroy
      redirect_back fallback_location: admin_calendar_index_path, notice: "All occurrences deleted."
    else
      head :bad_request
    end
  end

  private

  def unavailability_params
    params.require(:staff_unavailability).permit(
      :user_id, :title, :description, :utc_start_time, :utc_end_time, :recurrence_rule
    )
  end

  def update_single_unavailability
    if @staff_unavailability.update(
        title: unavailability_params[:title].presence || "Unavailable",
        description: ActionController::Base.helpers.strip_tags(unavailability_params[:description].to_s),
        start_time: unavailability_params[:utc_start_time],
        end_time: unavailability_params[:utc_end_time],
        recurrence_rule: unavailability_params[:recurrence_rule]
      )
      flash[:notice] = "Unavailability updated."
    else
      flash[:alert] = "Failed: #{@staff_unavailability.errors.full_messages.to_sentence}"
    end
  end

  def update_all_occurrences
    old_date_new_time_start = helpers.combine_date_and_time(
      @staff_unavailability.start_time.utc, 
      Time.parse(unavailability_params[:utc_start_time]).utc
    )
    duration = (Time.parse(unavailability_params[:utc_end_time]).utc - Time.parse(unavailability_params[:utc_start_time]).utc).to_i
    old_date_new_time_end = old_date_new_time_start + duration

    old_rrule, old_dtstart, old_extra_lines = helpers.parse_rrule_and_dtstart(@staff_unavailability.recurrence_rule)
    new_rrule, new_dtstart, _ = helpers.parse_rrule_and_dtstart(unavailability_params[:recurrence_rule])

    rule_to_use = if old_rrule == new_rrule
      combined_dtstart = old_dtstart.change(hour: new_dtstart.hour, min: new_dtstart.min, sec: new_dtstart.sec)
      (["DTSTART:#{combined_dtstart.strftime('%Y%m%dT%H%M%SZ')}", "RRULE:#{old_rrule}"] + old_extra_lines).join("\n")
    else
      unavailability_params[:recurrence_rule]
    end

    if @staff_unavailability.update(
        title: unavailability_params[:title].presence || "Unavailable",
        description: unavailability_params[:description],
        start_time: old_date_new_time_start,
        end_time: old_date_new_time_end,
        recurrence_rule: rule_to_use
      )
      flash[:notice] = "All occurrences updated."
    else
      flash[:alert] = "Failed: #{@staff_unavailability.errors.full_messages.to_sentence}"
    end
  end

  def update_this_occurrence
    exclusion_start_time = helpers.combine_date_and_time(
      Time.parse(unavailability_params[:utc_start_time]).utc, 
      @staff_unavailability.start_time.utc
    )
    updated_rule = helpers.add_exdate_to_rrule(@staff_unavailability.recurrence_rule, exclusion_start_time)
    @staff_unavailability.update(recurrence_rule: updated_rule)

    StaffUnavailability.create!(
      title: unavailability_params[:title].presence || "Unavailable",
      description: unavailability_params[:description],
      start_time: unavailability_params[:utc_start_time],
      end_time: unavailability_params[:utc_end_time],
      recurrence_rule: nil,
      user_id: @staff_unavailability.user_id
    )
    flash[:notice] = "This occurrence updated."
  end

  def delete_single_occurrence
    rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@unavailability.recurrence_rule)
    exdate = Time.parse(params[:start_date]).utc.strftime("%Y%m%dT%H%M%SZ")
    
    rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @unavailability.start_time)
    recurrence_lines = [
      "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}",
      "RRULE:#{rule}",
      "EXDATE:#{exdate}"
    ]
    
    @unavailability.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))
    redirect_back fallback_location: admin_calendar_index_path, notice: "This occurrence deleted."
  end

  def delete_following_occurrences
    rrule_line, dtstart, rest_of_lines = helpers.parse_rrule_and_dtstart(@unavailability.recurrence_rule)
    previous_day = Time.parse(params[:start_date]).utc - 24.hours
    rrule_line = "#{helpers.remove_until_from_rrule(rrule_line)};UNTIL=#{previous_day.strftime("%Y%m%dT%H%M%SZ")}"
    
    rule = RRule::Rule.new(rrule_line, dtstart: dtstart || @unavailability.start_time)
    recurrence_lines = [
      "DTSTART:#{rule.dtstart.utc.strftime("%Y%m%dT%H%M%SZ")}",
      "RRULE:#{rule}"
    ]
    
    @unavailability.update!(recurrence_rule: (recurrence_lines + rest_of_lines).join("\n"))
    redirect_back fallback_location: admin_calendar_index_path, notice: "This and following deleted."
  end
end