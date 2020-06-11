class Printer < ApplicationRecord
  has_many :printer_sessions,     dependent: :destroy
  scope :show_options, -> { order("lower(model) ASC").all }

  def model_and_number
    "#{model}; Number #{number}"
  end

  def self.get_printer_ids(model)
    return Printer.where(:model => model).pluck(:id)
  end

  def self.get_last_model_session(printer_model)
    return PrinterSession.joins(:printer).order(created_at: :desc)
               .where("printers.model = ?", printer_model).first
  end

  def self.get_last_number_session(printer_id)
    return PrinterSession.order(created_at: :desc).where(:printer_id => printer_id).first
  end

end
