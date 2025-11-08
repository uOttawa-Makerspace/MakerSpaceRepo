# frozen_string_literal: true

class PrinterTypesController < StaffAreaController
  before_action :get_printer_type, only: %i[edit update destroy]
  before_action :ensure_admin

  def index
    @printer_types = PrinterType.all.order("LOWER(name) ASC")
  end

  def new
    @printer_type = PrinterType.new
  end

  def create
    if printer_type_params[:name].blank?
      redirect_to new_printer_type_path, alert: "Please input a printer model"
    else
      @printer_type = PrinterType.new(printer_type_params)

      if @printer_type.save
        redirect_to printer_types_path,
                    notice: "Successfully created new printer model"
      else
        redirect_to new_printer_type_path, alert: "Printer model already exists"
      end
    end
  end

  def update
    if @printer_type.update(printer_type_params)
      flash[:notice] = "Successfully updated printer model"
    else
      flash[:alert] = "Failed to update printer model"
    end
    redirect_to printer_types_path
  end

  def destroy
    @printer_type.destroy

    redirect_to printer_types_path, notice: "Successfully deleted printer model"
  end

  private

  def printer_type_params
    params.require(:printer_type).permit(:name, :short_form, :available)
  end

  def get_printer_type
    @printer_type = PrinterType.find_by(id: params[:id])

    if @printer_type.nil?
      redirect_to printer_types_path, alert: "Couldn't find Printer Model"
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
