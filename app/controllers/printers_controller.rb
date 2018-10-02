class PrintersController < ApplicationController
  layout 'staff_area'

  def staff_printers
    @user = current_user
    @list_users = User.all.pluck(:name, :id)
    @printers = Printer.all
    @last_session_ultimaker = PrinterSession.joins(:printer).order(created_at: :desc)
                                      .where("printers.model = ?", "Ultimaker 2+").first
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

end
