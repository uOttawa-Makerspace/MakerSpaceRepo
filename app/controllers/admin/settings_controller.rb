# frozen_string_literal: true

class Admin::SettingsController < AdminAreaController
  layout "admin_area"

  def index
    @equip_option = EquipmentOption.new
    @cat_option = CategoryOption.new
    @pi_option = PiReader.new
    @job_order_processed_message = JobOrderMessage.find_by(name: "processed")
    @area_option = AreaOption.new
    @printer = Printer.new
    @printer_type = PrinterType.new
    @printer_models = PrinterType.all.order(name: :asc).pluck(:name, :id)
  end

  def add_category
    if params[:category_option][:name].blank?
      flash[:alert] = "Invalid category name."
    else
      @cat_option = CategoryOption.new(cat_params)
      @cat_option.save
      flash[:notice] = "Category added successfully!"
    end
    redirect_to admin_settings_path
  end

  def add_area
    if params[:area_option][:name].blank?
      flash[:alert] = "Invalid area name."
    else
      @area_option = AreaOption.new(area_params)
      @area_option.save
      flash[:notice] = "Area added successfully!"
    end
    redirect_to admin_settings_path
  end

  def add_printer
    if params[:printer][:number].blank? || params[:model_id].blank?
      flash[:alert] = "Invalid printer model or number"
    else
      @printer =
        Printer.new(printer_params.merge(printer_type_id: params[:model_id]))
      @printer.save
      flash[:notice] = "Printer added successfully!"
    end
    redirect_to admin_settings_path
  end

  def add_printer_type
    if params[:printer_type][:name].blank?
      flash[:alert] = "Please put in a printer model"
    else
      @printer_type = PrinterType.new(name: params[:printer_type][:name])
      if @printer_type.save
        flash[:notice] = "Successfully created new printer model"
      else
        flash[:alert] = "Printer model already exists"
      end
    end
    redirect_to admin_settings_path
  end

  def add_course
    @new_course = CourseName.new(course_params)
    if @new_course.save
      flash[:notice] = "Course added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_settings_path
  end

  def remove_course
    @course = CourseName.find(params[:id])
    if @course.destroy
      flash[:notice] = "Course removed successfully"
    else
      flash[:alert] = "There was an issue trying to remove the course"
    end
    redirect_to admin_settings_path
  end

  def rename_course
    @course = CourseName.find(params[:id])
    if @course.update(course_params.except(:id))
      flash[:notice] = "Course updated successfully"
    else
      flash[:alert] = "There was an issue trying to rename the course"
    end
    redirect_to admin_settings_path
  end

  # def rename_category
  #   if !params[:category_option][:name].present?
  #     flash[:alert] = "Invalid category name."
  #   elsif params[:rename_category]==""
  #     flash[:alert] = "Please select a category."
  #   else
  #     puts "params: #{params[:rename_category]}"
  #     CategoryOption.where(:id => params[:rename_category]).update_all(cat_params)
  #     flash[:notice] = "Category renamed successfully!"
  #   end
  #   redirect_to admin_settings_path
  # end

  def remove_category
    if params[:remove_category] != ""
      CategoryOption.where(id: params[:remove_category]).destroy_all
      flash[:notice] = "Category removed successfully!"
    else
      flash[:alert] = "Please select a category."
    end
    redirect_to admin_settings_path
  end

  def remove_area
    if params[:remove_area] != ""
      AreaOption.where(id: params[:remove_area]).destroy_all
      flash[:notice] = "Area removed successfully!"
    else
      flash[:alert] = "Please select an area."
    end
    redirect_to admin_settings_path
  end

  def remove_printer
    if params[:remove_printer] != ""
      Printer.where(id: params[:remove_printer]).destroy_all
      flash[:notice] = "Printer removed successfully!"
    else
      flash[:alert] = "Please select a Printer."
    end
    redirect_to admin_settings_path
  end

  def add_equipment
    if params[:equipment_option][:name].blank?
      flash[:alert] = "Invalid equipment name."
    else
      @equip_option = EquipmentOption.new(equip_params)
      @equip_option.save
      flash[:notice] = "Equipment added successfully!"
    end
    redirect_to admin_settings_path
  end

  def rename_equipment
    if params[:equipment_option][:name].blank?
      flash[:alert] = "Invalid equipment name."
    elsif params[:rename_equipment] == ""
      flash[:alert] = "Please select a piece of equipment."
    else
      EquipmentOption.where(id: params[:rename_equipment]).update_all(
        name: equip_params["name"]
      )
      flash[:notice] = "Equipment renamed successfully!"
    end
    redirect_to admin_settings_path
  end

  def remove_equipment
    if params[:remove_equipment] != ""
      EquipmentOption.where(id: params[:remove_equipment]).destroy_all
      flash[:notice] = "Equipment removed successfully!"
    else
      flash[:alert] = "Please select a piece of equipment."
    end
    redirect_to admin_settings_path
  end

  # def submit_pi
  #   puts "aiai"
  #   puts params
  #   if (!params[:pi_reader][:pi_location].present?) || (params[:submit_pi].blank?)
  #       flash[:alert] = "Invalid parameters."
  #   else
  #     PiReader.where(:id => params[:submit_pi]).update_all(pi_params)
  #     flash[:notice] = "Card reader location updated successfully!"
  #   end
  #   redirect_to admin_settings_path
  # end

  def remove_pi
    if params[:remove_pi] != ""
      PiReader.where(id: params[:remove_pi]).destroy_all
      flash[:notice] = "Card reader removed successfully!"
    else
      flash[:alert] = "Please select a card reader."
    end
    redirect_to admin_settings_path
  end

  def update_job_order_processed
    if params[:job_order_message].present? &&
         params[:job_order_message][:message].present?
      PrintOrderMessage.find_by(name: "processed").update(
        message: params[:job_order_message][:message]
      )
      flash[:notice] = "Message updated successfully!"
    else
      flash[:alert] = "Please enter a message."
    end
    redirect_to admin_settings_path
  end

  def pin_unpin_repository
    params.require(:repository_id)
    repo = Repository.find_by(id: params[:repository_id])

    if repo.update(featured: !repo.featured)
      flash[
        :notice
      ] = "Successfully #{repo.featured ? "Featured" : "Unfeatured"} repository"
    else
      flash[:alert] = "something went wrong"
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def pi_params
    params.require(:pi_reader).permit(:pi_location)
  end

  def equip_params
    params.require(:equipment_option).permit(:name)
  end

  def cat_params
    params.require(:category_option).permit(:name)
  end

  def area_params
    params.require(:area_option).permit(:name)
  end

  def printer_params
    params.require(:printer).permit(:number)
  end

  def course_params
    params.permit(:name, :id)
  end
end
