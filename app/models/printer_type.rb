class PrinterType < ApplicationRecord
  has_many :printers, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
