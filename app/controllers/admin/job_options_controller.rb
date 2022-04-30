class Admin::JobOptionsController < AdminAreaController
  before_action :set_job_option, only: %i[edit update destroy]

  def index; end

  def new
    @job_option = JobOption.new
  end

  def create
    @job_option = JobOption.new(job_option_params)
    if @job_option.save
      flash[:notice] = "The option has been created!"
    else
      flash[:alert] = "There was an error while creating the option."
    end
    redirect_to settings_job_orders_path
  end

  def edit; end

  def update
    if @job_option.update(job_option_params)
      flash[:notice] = 'The Service Group has been updated'
    else
      flash[:alert] = 'Something went wrong while updating the Service Group'
    end
    redirect_to settings_job_orders_path
  end

  def destroy
    if @job_option.destroy
      flash[:notice] = 'The option has been deleted successfully'
    else
      flash[:alert] = 'An error occurred while deleting the option.'
    end
    redirect_to settings_job_orders_path
  end

  private

  def job_option_params
    params.require(:job_option).permit(:name, :description, :need_files, :fee, job_type_ids: [])
  end

  def set_job_option
    @job_option = JobOption.find(params[:id])
  end
end
