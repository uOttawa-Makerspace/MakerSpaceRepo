class Admin::JobServicesController < AdminAreaController
  before_action :set_job_service, only: %i[edit update destroy]

  def index
  end

  def new
    @job_service = JobService.new
  end

  def create
    @job_service = JobService.new(job_service_params)
    if @job_service.save
      flash[:notice] = "The Service has been created!"
    else
      flash[:alert] = "There was an error while creating the Service."
    end
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    if @job_service.update(job_service_params)
      flash[:notice] = "The Service has been updated"
    else
      flash[:alert] = "Something went wrong while updating the Service"
    end
    redirect_to settings_job_orders_path
  end

  def destroy
    if @job_service.destroy
      flash[:notice] = "The Service has been deleted successfully"
    else
      flash[:alert] = "An error occurred while deleting the Service."
    end
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
