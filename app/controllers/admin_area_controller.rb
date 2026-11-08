# frozen_string_literal: true

class AdminAreaController < SessionsController
  include AdminOnly

  before_action :current_user
  before_action :ensure_admin

  private

  # Runs the write in the block and flashes `notice` when it succeeded. When it did not, flashes the
  # sentence at errors.admin.<key> followed by the record's validation messages (a write that raises
  # RecordInvalid, like the copy-on-edit of services, options and groups, names the record that failed).
  # A delete the database refuses because other records still point at the row says so instead.
  def flash_write(record, key, notice)
    if yield
      flash[:notice] = notice
    else
      flash[:alert] = validation_message(record, "errors.admin.#{key}")
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = validation_message(e.record, "errors.admin.#{key}")
  rescue ActiveRecord::InvalidForeignKey
    flash[:alert] = [I18n.t("errors.admin.#{key}"), I18n.t("errors.admin.still_in_use")].join(" ")
  end
end
