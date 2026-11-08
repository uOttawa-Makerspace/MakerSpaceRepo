# frozen_string_literal: true

class Admin::SettingsController < AdminAreaController
  layout "admin_area"

  def index
    @equip_option = EquipmentOption.new
    @cat_option = CategoryOption.new
    @pi_option = PiReader.new
    @job_order_processed_message = JobOrderMessage.find_by(name: "processed")
    @print_failed_message = JobOrderMessage.print_failed
    @area_option = AreaOption.new
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

  def add_course
    @new_course = CourseName.new(course_params)
    flash_write(@new_course, "settings.course_not_added", "Course added successfully!") { @new_course.save }
    redirect_to admin_settings_path
  end

  def remove_course
    @course = CourseName.find(params[:id])
    flash_write(@course, "settings.course_not_removed", "Course removed successfully") { @course.destroy }
    redirect_to admin_settings_path
  end

  def rename_course
    @course = CourseName.find(params[:id])
    flash_write(@course, "settings.course_not_renamed", "Course updated successfully") do
      @course.update(course_params.except(:id))
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
    msg = params.dig(:job_order_message, :message)
    update_job_order_message(JobOrderMessage.find_by(name: "processed"), msg)
  end

  def update_print_failed_message
    msg = params.dig(:job_order_message, :message)
    update_job_order_message(JobOrderMessage.print_failed, msg)
  end

  def pin_unpin_repository
    params.require(:repository_id)
    repo = Repository.find_by(id: params[:repository_id])

    flash_write(repo, "settings.repository_not_updated", "Successfully #{repo.featured ? "Unfeatured" : "Featured"} repository") do
      repo.update(featured: !repo.featured)
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def update_job_order_message(message, text)
    if text
      flash_write(message, "settings.message_not_updated", "Message updated successfully!") { message.update(message: text) }
    else
      flash[:alert] = I18n.t("errors.admin.settings.message_missing")
    end
    redirect_to admin_settings_path
  end

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
