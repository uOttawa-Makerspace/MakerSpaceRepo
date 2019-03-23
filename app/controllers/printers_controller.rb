class PrintersController < ApplicationController
  before_action :current_user, :user_staff
  layout 'staff_area'

  def staff_printers
    @printers = Printer.all
    @list_users = User.joins(:lab_sessions => :space).where("lab_sessions.sign_out_time > ? AND spaces.name = ?", Time.zone.now, "Makerspace").order("lab_sessions.sign_out_time DESC").pluck(:name, :id)
    @last_session_ultimaker = Printer.get_last_model_session("Ultimaker 2+")
    @last_session_ultimaker3 = Printer.get_last_model_session("Ultimaker 3")
    @last_session_replicator2 = Printer.get_last_model_session("Replicator 2")
    @last_session_dremel = Printer.get_last_model_session("Dremel")
  end

  def staff_printers_updates
    @ultimaker_printer_ids = Printer.get_printer_ids("Ultimaker 2+")
    @ultimaker3_printer_ids = Printer.get_printer_ids("Ultimaker 3")
    @replicator2_printer_ids = Printer.get_printer_ids("Replicator 2")
    @dremel_printer_ids = Printer.get_printer_ids("Dremel")
  end

  def link_printer_to_user
    printer_id = params[:printer][:printer_id]
    user_id = params[:printer][:user_id]
    if !printer_id.present? || !user_id.present?
      flash[:alert] = "Please add both printer and user."
    elsif PrinterSession.create(:printer_id => printer_id, :user_id => user_id)
      flash[:notice] = "Printer Session Created"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to staff_printers_printers_path
  end

  private

  def user_staff
    @user = current_user
    unless @user.staff? || @user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to '/' and return
    end
  end

end
