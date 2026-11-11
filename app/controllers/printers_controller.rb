# frozen_string_literal: true

class PrintersController < StaffAreaController
  layout "staff_area"

  before_action :ensure_admin, only: %i[index add_printer remove_printer]

  def index
    @printer = Printer.new
    @printer_models =
      PrinterType
        .all
        .order(name: :asc)
        .map do |pt|
          [pt.name + (pt.short_form.blank? ? "" : " (#{pt.short_form})"), pt.id]
        end
  end

  def update
    printer = Printer.find(params[:id])
    if printer.update(printer_params)
      flash[:notice] = "Printer #{printer.name} updated"
    else
      flash[:alert] = "Failed to update printer"
    end

    redirect_back fallback_location: printers_path
  end

  def add_printer
    if params[:printer][:number].blank? || params[:model_id].blank?
      flash[:alert] = "Invalid printer model or number"
    else
      number = params[:printer][:number]

      @printer = Printer.new(number: number, printer_type_id: params[:model_id])
      if @printer.save
        flash[:notice] = "Printer added successfully!"
      else
        flash[:alert] = "Printer number already exists"
      end
    end
    # pass the model to keep selection
    if params[:model_id]&.empty?
      redirect_to printers_path
    else
      redirect_to printers_path(model_id: params[:model_id])
    end
  end

  def remove_printer
    printer_id = params[:remove_printer].to_s
    printer = Printer.find_by(id: printer_id) if printer_id.present?
    if printer_id.blank?
      flash[:alert] = "Please select a Printer."
    elsif printer.nil?
      flash[:alert] = I18n.t("errors.printers.printer_not_found")
    elsif printer.destroy
      flash[:notice] = "Printer removed successfully!"
    else
      flash[:alert] = validation_message(printer, "errors.printers.printer_not_removed")
    end
    redirect_to printers_path
  end

  def staff_printers
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
    @printer_types = PrinterType.includes(:printers).order("lower(name) ASC")
  end

  def staff_printers_updates
    @printer_types = PrinterType.all.order("lower(name) ASC")
  end

  def link_printer_to_user
    link_params = params.require(:printer).permit(:printer_id, :user_id)
    printer_id = link_params[:printer_id]
    user_id = link_params[:user_id]
    last_session = Printer.get_last_number_session(printer_id)
    printer_session = PrinterSession.new(printer_id: printer_id, user_id: user_id, in_use: true)
    if (problem = printer_link_problem(printer_id, user_id))
      flash[:alert] = I18n.t("errors.printers.#{problem}")
    elsif user_id == "clear"
      last_session&.update(in_use: false)
      flash[:notice] = "Cleared the user."
    elsif printer_session.save
      last_session.update(in_use: false) if last_session&.in_use?
      flash[:notice] = "Printer Session Created"
    else
      flash[:alert] = validation_message(printer_session, "errors.printers.session_not_created")
    end
    respond_to do |format|
      # blame the client if something goes wrong
      format.json do
        render json: flash, status: flash[:alert] ? :bad_request : :ok
      end
      format.html { redirect_to staff_printers_printers_path }
    end
  end

  # Why a printer cannot be linked to a user (a key under errors.printers), or nil.
  def printer_link_problem(printer_id, user_id)
    return :printer_and_user_required if printer_id.blank? || user_id.blank?
    return :printer_not_found unless Printer.exists?(printer_id)

    :user_not_found unless user_id == "clear" || User.exists?(user_id)
  end
  private :printer_link_problem

  def send_print_failed_message_to_user
    msg_params = params[:print_failed_message]
    print_owner = User.find_by(username: msg_params[:username])
    printer = Printer.find_by(id: msg_params[:printer_number])

    if printer.nil?
      flash[:alert] = "Error sending message, printer not found"
    elsif print_owner.nil?
      flash[:alert] = "Error sending message, username not found"
    else
      MsrMailer.print_failed(
        printer,
        print_owner,
        msg_params[:staff_notes]
      ).deliver_now

      flash[:notice] = "Email sent successfully"
    end

    if msg_params[:sent_from] == "updates"
      redirect_to staff_printers_updates_printers_url
    else
      redirect_to staff_printers_printers_url
    end
  end

  # Keep it all in one to reduce network requests
  def printer_data
    data =
      PrinterType
        .includes(printers: :printer_issues)
        .all
        .map do |type|
          {
            id: type.id,
            name: type.name,
            short_form: type.short_form,
            available: type.available,
            printers:
              type.printers.map do |p|
                {
                  id: p.id,
                  number: p.number,
                  maintenance: p.maintenance,
                  has_issues: !p.printer_issues.empty?
                }
              end
          }
        end

    respond_to do |format|
      format.html { redirect_to root_path }
      format.json { render json: data }
    end
  end

  def last_user_assigned_to_printer
    printer_users = {}
    Printer.includes(printer_sessions: :user).find_each do |printer|
      user = printer.printer_sessions.last&.user
      printer_users[printer.id] = user.slice(:id, :username, :name) if user
    end

    render json: printer_users
  end

  private

  def printer_params
    if current_user.admin?
      params.require(:printer).permit(:number, :maintenance)
    else
      params.require(:printer).permit(:maintenance)
    end
  end

  def ensure_admin
    @user = current_user

    unless @user.admin?
      flash[:alert] = "You cannot access this area"
      redirect_back(fallback_location: root_path)
    end
  end
end
