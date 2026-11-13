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
    if cat_params[:name].blank?
      flash[:alert] = I18n.t("admin_pages.settings.flash.invalid_category")
    else
      @cat_option = CategoryOption.new(cat_params)
      @cat_option.save
      flash[:notice] = I18n.t("admin_pages.settings.flash.category_added")
    end
    redirect_to admin_settings_path
  end

  def add_area
    if area_params[:name].blank?
      flash[:alert] = I18n.t("admin_pages.settings.flash.invalid_area")
    else
      @area_option = AreaOption.new(area_params)
      @area_option.save
      flash[:notice] = I18n.t("admin_pages.settings.flash.area_added")
    end
    redirect_to admin_settings_path
  end

  def add_course
    @new_course = CourseName.new(course_params)
    flash_write(@new_course, "settings.course_not_added", I18n.t("admin_pages.settings.flash.course_added")) { @new_course.save }
    redirect_to admin_settings_path
  end

  def remove_course
    @course = CourseName.find(params[:id])
    flash_write(@course, "settings.course_not_removed", I18n.t("admin_pages.settings.flash.course_removed"), destroy: true) { @course.destroy }
    redirect_to admin_settings_path
  end

  def rename_course
    @course = CourseName.find(params[:id])
    flash_write(@course, "settings.course_not_renamed", I18n.t("admin_pages.settings.flash.course_updated")) do
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
    option = CategoryOption.find_by(id: params[:remove_category])
    if option.nil?
      flash[:alert] = I18n.t("admin_pages.settings.flash.select_category")
    elsif option.in_use?
      flash[:alert] = I18n.t("errors.admin.settings.category_in_use")
    else
      option.destroy
      flash[:notice] = I18n.t("admin_pages.settings.flash.category_removed")
    end
    redirect_to admin_settings_path
  end

  def remove_area
    option = AreaOption.find_by(id: params[:remove_area])
    if option
      option.destroy
      flash[:notice] = I18n.t("admin_pages.settings.flash.area_removed")
    else
      flash[:alert] = I18n.t("admin_pages.settings.flash.select_area")
    end
    redirect_to admin_settings_path
  end

  def add_equipment
    if equip_params[:name].blank?
      flash[:alert] = I18n.t("admin_pages.settings.flash.invalid_equipment")
    else
      @equip_option = EquipmentOption.new(equip_params)
      @equip_option.save
      flash[:notice] = I18n.t("admin_pages.settings.flash.equipment_added")
    end
    redirect_to admin_settings_path
  end

  def rename_equipment
    if equip_params[:name].blank?
      flash[:alert] = I18n.t("admin_pages.settings.flash.invalid_equipment")
    elsif (option = EquipmentOption.find_by(id: params[:rename_equipment])).nil?
      flash[:alert] = I18n.t("admin_pages.settings.flash.select_equipment")
    else
      option.update(name: equip_params[:name])
      flash[:notice] = I18n.t("admin_pages.settings.flash.equipment_renamed")
    end
    redirect_to admin_settings_path
  end

  def remove_equipment
    option = EquipmentOption.find_by(id: params[:remove_equipment])
    if option
      option.destroy
      flash[:notice] = I18n.t("admin_pages.settings.flash.equipment_removed")
    else
      flash[:alert] = I18n.t("admin_pages.settings.flash.select_equipment")
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
      flash[:notice] = I18n.t("admin_pages.settings.flash.card_reader_removed")
    else
      flash[:alert] = I18n.t("admin_pages.settings.flash.select_card_reader")
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

    flash_write(repo, "settings.repository_not_updated", repo.featured ? I18n.t("admin_pages.settings.flash.repository_unfeatured") : I18n.t("admin_pages.settings.flash.repository_featured")) do
      repo.update(featured: !repo.featured)
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def update_job_order_message(message, text)
    if text
      flash_write(message, "settings.message_not_updated", I18n.t("admin_pages.settings.flash.message_updated")) { message.update(message: text) }
    else
      flash[:alert] = I18n.t("errors.admin.settings.message_missing")
    end
    redirect_to admin_settings_path
  end

  def pi_params
    params.require(:pi_reader).permit(:pi_location)
  end

  def equip_params
    params.expect(equipment_option: [:name])
  end

  def cat_params
    params.expect(category_option: [:name])
  end

  def area_params
    params.expect(area_option: [:name])
  end

  def printer_params
    params.require(:printer).permit(:number)
  end

  def course_params
    params.permit(:name, :id)
  end
end
