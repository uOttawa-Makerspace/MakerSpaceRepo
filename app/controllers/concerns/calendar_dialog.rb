# frozen_string_literal: true

# How the calendar dialogs answer a save or a delete. A Turbo form gets a stream that shows the flash, closes the
# dialog and refetches the calendar's events; any other request is redirected back to the page it came from, or to the admin calendar (a controller may override
# `after_dialog_path`).
module CalendarDialog
  extend ActiveSupport::Concern

  private

  def dialog_done(notice: nil, alert: nil)
    flash.update({ notice: notice, alert: alert }.compact)
    respond_to do |format|
      format.html { redirect_to after_dialog_path }
      format.turbo_stream do
        flash.discard
        render "calendar_dialog/done"
      end
    end
  end

  def after_dialog_path
    url_from(request.referer) || admin_calendar_index_path
  end
end
