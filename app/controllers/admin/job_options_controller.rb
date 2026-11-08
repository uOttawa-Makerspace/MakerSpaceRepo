class Admin::JobOptionsController < AdminAreaController
  before_action :set_job_option, only: %i[edit update destroy]

  def new
    @job_option = JobOption.new
  end

  def create
    @job_option = JobOption.new(job_option_params)
    flash_write(@job_option, "job_options.not_created", "The option has been created!") { @job_option.save }
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    flash_write(@job_option, "job_options.not_updated", "The Service Group has been updated") { @job_option.update(job_option_params) }
    redirect_to settings_job_orders_path
  end

  def destroy
    flash_write(@job_option, "job_options.not_deleted", "The option has been deleted successfully") { @job_option.destroy }
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
