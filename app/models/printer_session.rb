# frozen_string_literal: true

class PrinterSession < ApplicationRecord
  belongs_to :printer, optional: true
  belongs_to :user, optional: true
  has_one :printer_type, through: :printer

  # Releases every printer still marked in use (config/recurring.yml, nightly). Returns how many it released.
  def self.clear_in_use!
    where(in_use: true).update_all(in_use: false, updated_at: Time.current)
  end
end
