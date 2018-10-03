class PrintersController < ApplicationController
  before_action :current_user, :ensure_staff
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
    @list_users = User.all.pluck(:name, :id)
    @last_session_ultimaker = Printer.get_last_model_session("Ultimaker 2+")
    @last_session_replicator2 = Printer.get_last_model_session("Replicator 2")
    @last_session_replicator2x = Printer.get_last_model_session("Replicator 2x")
    @last_session_dremel = Printer.get_last_model_session("Dremel")
  end

  def staff_printers_updates
    @ultimaker_printer_ids = Printer.get_printer_ids("Ultimaker 2+")
    @replicator2_printer_ids = Printer.get_printer_ids("Replicator 2")
    @replicator2x_printer_ids = Printer.get_printer_ids("Replicator 2x")
    @dremel_printer_ids = Printer.get_printer_ids("Dremel")
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

  private

  def ensure_staff
    @user = current_user
    unless @user.staff? || @user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to '/'
    end
  end

end
