# frozen_string_literal: true

# One line for the usual "write, then flash the outcome" step of a controller action.
module FlashWrite
  extend ActiveSupport::Concern

  private

  # Runs the block (a save, update or destroy) and flashes `notice` when it succeeded. When it did
  # not, flashes the sentence at the i18n `key` followed by the record's validation messages.
  def write_flash(record, key, notice)
    if yield
      flash[:notice] = notice
    else
      flash[:alert] = validation_message(record, key)
    end
  end
end
