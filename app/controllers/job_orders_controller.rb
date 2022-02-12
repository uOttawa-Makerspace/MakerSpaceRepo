class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[index new create update destroy]
  before_action :wizard, only: %w[new]

  def index
    @job_orders = @user.job_orders
  end

  def new
    @job_order = JobOrder.new
    @job_order.assign_attributes(params[:job_order].present? ? job_order_params : {})
    case @step
    when 1
      render 'job_orders/wizard/order_type'
    when 2
      @job_type = JobType.find(@job_order.job_type_id)
      @service_groups = JobServiceGroup.find_by(job_type: @job_order.job_type)
      render 'job_orders/wizard/service'
    when 3
      render 'job_orders/wizard/options'
    when 4
      render 'job_orders/wizard/submission'
    end
  end

  def edit

  end

  def create

  end

  def update

  end

  def destroy

  end

  def admin
    @job_orders = JobOrder.all
  end

  def settings
    @service_groups = JobServiceGroup.all.order(:job_type_id)
    @services = JobService.all.order(:job_service_group_id)
    @options = JobOption.all
  end

  private

  def job_order_params
    params.require(:job_order).permit(:user_id, :job_type_id, user_files: [])
  end

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = 'You cannot access this area.'
      redirect_to root_path
    end
  end

  def wizard
    if params[:step].present? && session[:step].present?
      if (params[:step].to_i - 1) <= session[:step].to_i
        session[:step] = params[:step].to_i
      end
    else
      session[:step] = 1
    end
    @step = session[:step]
  end

end
