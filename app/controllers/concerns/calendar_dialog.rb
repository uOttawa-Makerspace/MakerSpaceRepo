# frozen_string_literal: true

# How the calendar dialogs answer a save or a delete. A Turbo form gets a stream that shows the flash, closes the
# dialog and refetches the calendar's events; any other request is redirected back to the page it came from, or to
# the admin calendar (a controller may override `after_dialog_path`).
module CalendarDialog
  extend ActiveSupport::Concern

  private

  # A redirect carries the messages to the next page; a stream shows them in this response only.
  def dialog_done(notice: nil, alert: nil)
    respond_to do |format|
      format.html { redirect_to after_dialog_path, notice: notice, alert: alert }
      format.turbo_stream do
        { notice: notice, alert: alert }.compact.each { |kind, text| flash.now[kind] = text }
        render "calendar_dialog/done"
      end
    end
  end

  def after_dialog_path
    url_from(request.referer) || admin_calendar_index_path
  end

  # Cuts the series of `record` (change: :without_occurrence or :ending_before) at the occurrence the dialog was
  # opened on (`start_date`). False, and nothing saved, when the dialog sent no usable start.
  def shorten_series(record, change)
    start = parse_time(params[:start_date])
    return false unless start

    record.update!(recurrence_rule: RecurrenceRule.new(record.recurrence_rule, record.start_time).public_send(change, start))
  end

  # The time as UTC, or nil when the text is missing or not a time.
  def parse_time(time_string)
    return nil if time_string.blank?

    Time.parse(time_string).utc
  rescue ArgumentError
    nil
  end
end
