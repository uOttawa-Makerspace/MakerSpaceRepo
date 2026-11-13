# frozen_string_literal: true

# How the calendar dialogs answer a save or a delete. A Turbo form gets a stream that shows the flash, closes the
# dialog and refetches the calendar's events; any other request is redirected back to the page it came from, or to
# the admin calendar (a controller may override `after_dialog_path`).
module CalendarDialog
  extend ActiveSupport::Concern

  private

  # The flash of this answer: only for this response when it is a stream, for the next page when it is a redirect.
  def dialog_flash
    request.format.turbo_stream? ? flash.now : flash
  end

  def dialog_done(notice: nil, alert: nil)
    { notice: notice, alert: alert }.compact.each { |kind, text| dialog_flash[kind] = text }
    respond_to do |format|
      format.html { redirect_to after_dialog_path }
      format.turbo_stream { render "calendar_dialog/done" }
    end
  end

  def after_dialog_path
    url_from(request.referer) || admin_calendar_index_path
  end

  # Gives `record` the series rule the block builds for the occurrence the dialog was opened on (`start_date`), then
  # answers with `notice`, or with `start_missing` when the dialog sent no usable start.
  def shorten_series(record, notice, start_missing, **changes)
    start = parse_time(params[:start_date])
    return dialog_done(alert: start_missing) unless start

    record.update!(recurrence_rule: yield(start), **changes)
    record.try(:push_to_google_later)
    dialog_done(notice: notice)
  end

  # The time as UTC, or nil when the text is missing or not a time.
  def parse_time(time_string)
    return nil if time_string.blank?

    Time.parse(time_string).utc
  rescue ArgumentError
    nil
  end
end
