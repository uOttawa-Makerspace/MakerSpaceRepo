class PrinterType < ApplicationRecord
  has_many :printers

  validates :name, presence: true
end
