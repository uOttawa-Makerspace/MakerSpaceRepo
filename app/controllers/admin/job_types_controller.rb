class Admin::JobTypesController < AdminAreaController
  before_action :set_job_type, only: %i[edit update]

  def new
    @job_type = JobType.new
  end

  def create
    @job_type = JobType.new(job_type_params)
    flash_write(@job_type, "job_types.not_created", "The Job Type has been created!") { @job_type.save }
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    flash_write(@job_type, "job_types.not_updated", "The Job Type has been updated") { @job_type.update(job_type_params) }
    redirect_to settings_job_orders_path
  end

  # def destroy
  #   if @job_type.destroy
  #     flash[:notice] = 'The Job Type has been deleted successfully'
  #   else
  #     flash[:alert] = 'An error occurred while deleting the Job Type.'
  #   end
  #   redirect_to settings_job_orders_path
  # end

  private

  def job_type_params
    params.require(:job_type).permit(
      :name,
      :comments,
      :service_fee,
      :multiple_files
    )
  end

  def set_job_type
    @job_type = JobType.find(params[:id])
  end
end
