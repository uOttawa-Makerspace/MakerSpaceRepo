# frozen_string_literal: true

# The staff of a space ranked for an event the admin is planning in the event dialog (StaffSpace.conflicts_for).
class Admin::Calendar::StaffConflictsController < AdminAreaController
  include CalendarWindowed

  def index
    window = CalendarWindow.bounded(params)
    rule = params[:recurrence_rule].presence
    error = rule && RecurrenceRuleValidator.error_for(rule, window.from)
    return render(json: { error: error }, status: :unprocessable_entity) if error

    render json: StaffSpace.conflicts_for(params[:space_id], rule: rule, window: window)
  end
end
