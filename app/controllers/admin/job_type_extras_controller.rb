class Admin::JobTypeExtrasController < AdminAreaController
  before_action :set_job_type_extra, only: %i[edit update destroy]

  def index; end

  def new
    @job_type_extra = JobTypeExtra.new
  end

  def create
    @job_type_extra = JobTypeExtra.new(job_type_extra_params)
    if @job_type_extra.save
      flash[:notice] = "The Job Type Extra has been created!"
    else
      flash[:alert] = "There was an error while creating the Job Type Extra."
    end
    redirect_to settings_job_orders_path
  end

  def edit; end

  def update
    if @job_type_extra.update(job_type_extra_params)
      flash[:notice] = 'The Job Type Extra has been updated'
    else
      flash[:alert] = 'Something went wrong while updating the Job Type Extra'
    end
    redirect_to settings_job_orders_path
  end

  def destroy
    if @job_type_extra.destroy
      flash[:notice] = 'The Job Type Extra has been deleted successfully'
    else
      flash[:alert] = 'An error occurred while deleting the Job Type Extra.'
    end
    redirect_to settings_job_orders_path
  end

  private

  def job_type_extra_params
    params.require(:job_type_extra).permit(:name, :amount, :job_type_id)
  end

  def set_job_type_extra
    @job_type_extra = JobTypeExtra.find(params[:id])
  end

end

