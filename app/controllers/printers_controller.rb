# frozen_string_literal: true

class PrintersController < StaffAreaController
  layout "staff_area"

  def staff_printers
    @printers = Printer.all
    @list_users =
      User
        .joins(lab_sessions: :space)
        .where(
          "lab_sessions.sign_out_time > ? AND spaces.name = ?",
          Time.zone.now,
          "Makerspace"
        )
        .order("lab_sessions.sign_out_time DESC")
        .uniq
        .pluck(:name, :id)
    @list_users.unshift(%w[Clear clear])
    @printer_types = PrinterType.all.pluck(:name)
  end

  def staff_printers_updates
    @printer_types = PrinterType.all.pluck(:name)
  end

  def link_printer_to_user
    printer_id = params[:printer][:printer_id]
    last_session = Printer.get_last_number_session(printer_id)
    user_id = params[:printer][:user_id]
    if printer_id.blank? || user_id.blank?
      flash[:alert] = "Please add both printer and user."
    elsif user_id == "clear" && last_session.update(in_use: false)
      flash[:notice] = "Cleared the user."
    elsif PrinterSession.create(
          printer_id: printer_id,
          user_id: user_id,
          in_use: true
        )
      if !last_session.nil? && last_session.in_use?
        last_session.update(in_use: false)
      end
      flash[:notice] = "Printer Session Created"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to staff_printers_printers_path
  end
end
