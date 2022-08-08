class Admin::JobServiceGroupsController < AdminAreaController
  before_action :set_job_service_group, only: %i[edit update destroy]

  def index
  end

  def new
    @job_service_group = JobServiceGroup.new
  end

  def create
    @job_service_group = JobServiceGroup.new(job_service_group_params)
    if @job_service_group.save
      flash[:notice] = "The Service Group has been created!"
    else
      flash[:alert] = "There was an error while creating the Service Group."
    end
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    if @job_service_group.update(job_service_group_params)
      flash[:notice] = "The Service Group has been updated"
    else
      flash[:alert] = "Something went wrong while updating the Service Group"
    end
    redirect_to settings_job_orders_path
  end

  def destroy
    if @job_service_group.destroy
      flash[:notice] = "The Service Group has been deleted successfully"
    else
      flash[:alert] = "An error occurred while deleting the Service Group."
    end
    redirect_to settings_job_orders_path
  end

  private

  def job_service_group_params
    params.require(:job_service_group).permit(
      :name,
      :description,
      :text_field,
      :multiple,
      :job_type_id
    )
  end

  def set_job_service_group
    @job_service_group = JobServiceGroup.find(params[:id])
  end
end
