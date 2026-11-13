class Admin::JobOptionsController < AdminAreaController
  before_action :set_job_option, only: %i[edit update destroy]

  def new
    @job_option = JobOption.new
  end

  def create
    @job_option = JobOption.new(job_option_params)
    flash_write(@job_option, "job_options.not_created", I18n.t("admin_pages.job_settings.flash.option_created")) { @job_option.save }
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    flash_write(@job_option, "job_options.not_updated", I18n.t("admin_pages.job_settings.flash.option_updated")) { @job_option.update(job_option_params) }
    redirect_to settings_job_orders_path
  end

  def destroy
    flash_write(@job_option, "job_options.not_deleted", I18n.t("admin_pages.job_settings.flash.option_deleted"), destroy: true) { @job_option.destroy }
    redirect_to settings_job_orders_path
  end

  private

  def job_option_params
    params.require(:job_option).permit(
      :name,
      :description,
      :need_files,
      :fee,
      :is_job_wide,
      job_type_ids: []
    )
  end

  def set_job_option
    @job_option = JobOption.find(params[:id])
  end
end
