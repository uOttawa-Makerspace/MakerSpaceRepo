# frozen_string_literal: true

class Printer < ApplicationRecord
  has_many :printer_sessions, dependent: :destroy
  belongs_to :printer_type, optional: true
  scope :show_options,
        -> { joins(:printer_type).order("lower(printer_types.name) ASC") }

  validates :number, presence: true, uniqueness: { scope: :printer_type_id }

  def model_and_number
    "#{printer_type.name}; Number #{number}"
  end

  def self.get_printer_ids(model)
    PrinterType.find_by(name: model).printers.pluck(:id)
  end

  def self.get_last_model_session(printer_model)
    PrinterSession
      .joins(:printer_type)
      .order(created_at: :desc)
      .where("printer_types.name = ?", printer_model)
      .first
  end

  def self.get_last_number_session(printer_id)
    PrinterSession.order(created_at: :desc).where(printer_id: printer_id).first
  end
end
