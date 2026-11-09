class Admin::JobServiceGroupsController < AdminAreaController
  before_action :set_job_service_group, only: %i[edit update destroy]

  def new
    @job_service_group = JobServiceGroup.new
  end

  def create
    @job_service_group = JobServiceGroup.new(job_service_group_params)
    flash_write(@job_service_group, "job_service_groups.not_created", "The Service Group has been created!") { @job_service_group.save }
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    flash_write(@job_service_group, "job_service_groups.not_updated", "The Service Group has been updated") { @job_service_group.update(job_service_group_params) }
    redirect_to settings_job_orders_path
  end

  def destroy
    flash_write(@job_service_group, "job_service_groups.not_deleted", "The Service Group has been deleted successfully", destroy: true) { @job_service_group.destroy }
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
