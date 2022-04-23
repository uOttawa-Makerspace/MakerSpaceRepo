# frozen_string_literal: true

class PrintersController < StaffAreaController
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
    @list_users = User.joins(lab_sessions: :space).where('lab_sessions.sign_out_time > ? AND spaces.name = ?', Time.zone.now, 'Makerspace').order('lab_sessions.sign_out_time DESC').uniq.pluck(:name, :id)
    @printer_types = [
      {
        name: 'Ultimaker 2+',
        id: 'ultimaker2p'
      },
      {
        name: 'Ultimaker 3',
        id: 'ultimaker3'
      },
      {
        name: 'Replicator 2',
        id: 'replicator2'
      },
      {
        name: 'Dremel',
        id: 'dremel'
      }
    ]
  end

  def staff_printers_updates
    @ultimaker_printer_ids = Printer.get_printer_ids('Ultimaker 2+')
    @ultimaker3_printer_ids = Printer.get_printer_ids('Ultimaker 3')
    @replicator2_printer_ids = Printer.get_printer_ids('Replicator 2')
    @dremel_printer_ids = Printer.get_printer_ids('Dremel')
    @printer_types = ['Ultimaker 2+', 'Ultimaker 3', 'Replicator 2', 'Dremel']
  end

  def link_printer_to_user
    printer_id = params[:printer][:printer_id]
    user_id = params[:printer][:user_id]
    if printer_id.blank? || user_id.blank?
      flash[:alert] = 'Please add both printer and user.'
    elsif PrinterSession.create(printer_id: printer_id, user_id: user_id)
      flash[:notice] = 'Printer Session Created'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to staff_printers_printers_path
  end

end
