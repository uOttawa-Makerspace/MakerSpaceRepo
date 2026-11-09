class Admin::JobServicesController < AdminAreaController
  before_action :set_job_service, only: %i[edit update destroy]

  def new
    @job_service = JobService.new
  end

  def create
    @job_service = JobService.new(job_service_params)
    flash_write(@job_service, "job_services.not_created", "The Service has been created!") { @job_service.save }
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    flash_write(@job_service, "job_services.not_updated", "The Service has been updated") { @job_service.update(job_service_params) }
    redirect_to settings_job_orders_path
  end

  def destroy
    flash_write(@job_service, "job_services.not_deleted", "The Service has been deleted successfully", destroy: true) { @job_service.destroy }
    redirect_to settings_job_orders_path
  end

  private

  def job_service_params
    params.require(:job_service).permit(
      :name,
      :description,
      :unit,
      :required,
      :internal_price,
      :external_price,
      :job_service_group_id,
      :job_order_id
    )
  end

  def set_job_service
    @job_service = JobService.find(params[:id])
  end
end
