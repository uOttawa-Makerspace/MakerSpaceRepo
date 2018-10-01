class PrintersController < ApplicationController
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
  end

  def link_printer_to_user


  end

end
