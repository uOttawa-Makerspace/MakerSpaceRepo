class Admin::JobTypesController < AdminAreaController
  before_action :set_job_type, only: %i[edit update]

  def index
  end

  def new
    @job_type = JobType.new
  end

  def create
    @job_type = JobType.new(job_type_params)
    if @job_type.save
      flash[:notice] = "The Job Type has been created!"
    else
      flash[:alert] = "There was an error while creating the Job Type."
    end
    redirect_to settings_job_orders_path
  end

  def edit
  end

  def update
    if @job_type.update(job_type_params)
      flash[:notice] = "The Job Type has been updated"
    else
      flash[:alert] = "Something went wrong while updating the Job Type"
    end
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
