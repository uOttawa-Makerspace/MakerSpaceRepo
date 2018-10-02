class PrintersController < ApplicationController
  before_action :current_user
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
    @list_users = User.all.pluck(:name, :id)
    @last_session_ultimaker = get_last_model_session("Ultimaker 2+")
    @last_session_replicator2 = get_last_model_session("Replicator 2")
    @last_session_replicator2x = get_last_model_session("Replicator 2x")
    @last_session_dremel = get_last_model_session("Dremel")
  end

  def staff_printers_updates
    @list_users = User.all.pluck(:name, :id)
    @printers = Printer.all
    @last_session_ultimaker = get_last_model_session("Ultimaker 2+")
    @last_session_replicator2 = get_last_model_session("Replicator 2")
    @last_session_replicator2x = get_last_model_session("Replicator 2x")
    @last_session_dremel = get_last_model_session("Dremel")
  end

  def link_printer_to_user
    printer_id = params[:printer][:printer_id]
    user_id = params[:printer][:user_id]
    if PrinterSession.create(:printer_id => printer_id, :user_id => user_id)
      flash[:notice] = "Printer Session Created"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to :back
  end

  def get_last_model_session(printer_model)
    return PrinterSession.joins(:printer).order(created_at: :desc)
               .where("printers.model = ?", printer_model).first
  end

  def get_last_number_session(printer_model, number)
    return PrinterSession.joins(:printer).order(created_at: :desc)
               .where("printers.model = ? AND printers.number = ?", printer_model, number).first
  end

end
