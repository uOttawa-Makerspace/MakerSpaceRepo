class PrintersController < ApplicationController
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
    @last_session_ultimaker = PrinterSession.joins(:printer).order(created_at: :desc)
                                      .where("printers.model = ?", "Ultimaker 2+").last
  end

  def link_printer_to_user


  end

end
