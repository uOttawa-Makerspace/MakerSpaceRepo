# frozen_string_literal: true

# The staff of a space ranked for an event the admin is planning in the event dialog: the event's occurrences over
# the next four weeks (just itself when it does not repeat), expanded by RecurringSeries, against each staff member's
# stored and external-calendar unavailabilities (StaffSpace.conflicts).
class Admin::Calendar::StaffConflictsController < AdminAreaController
  include CalendarWindowed

  HORIZON = 4.weeks

  def show
    window = CalendarWindow.bounded(params)
    rule = params[:recurrence_rule].presence
    error = rule && RecurrenceRuleValidator.error_for(rule, window.from)
    return render(json: { error: error }, status: :unprocessable_entity) if error

    proposal = RecurringSeries.new(rule: rule, starts_at: window.from, ends_at: window.to)
    render json: StaffSpace.conflicts(params[:space_id], proposal.occurrences_in(CalendarWindow.new(window.from, window.from + HORIZON)))
  end
end
