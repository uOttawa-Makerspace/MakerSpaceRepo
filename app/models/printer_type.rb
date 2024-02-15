class PrinterType < ApplicationRecord
  has_many :printers, dependent: :destroy
  has_many :printer_sessions, through: :printers

  validates :name, presence: true, uniqueness: true
end
