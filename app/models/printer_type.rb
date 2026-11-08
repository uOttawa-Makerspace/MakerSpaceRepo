class PrinterType < ApplicationRecord
  # A type with printers (and so their sessions and issues) cannot be deleted; remove or move the printers first.
  has_many :printers, dependent: :restrict_with_error
  has_many :printer_sessions, through: :printers

  validates :name, presence: true, uniqueness: true

  scope :available, -> { where(available: true) }
  scope :unavailable, -> { where(available: false) }
end
