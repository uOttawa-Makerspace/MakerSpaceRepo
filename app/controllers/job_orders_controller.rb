class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[index new create update destroy]
  before_action :wizard, only: %w[new]

  def index
    @job_orders = @user.job_orders
  end

  def new
    # After step 2 or more
    if params[:job_order].present? && params[:job_order][:id].present? && JobOrder.find(params[:job_order][:id]).user == @user
      @job_order = JobOrder.find(params[:job_order][:id])

      if params[:job_service_name].present?
        @job_order.job_services << JobService.create!(name: params[:job_service_name], job_service_group_id: @job_order.job_service_group_id, user_created: true)
      end

      @job_order.update(job_order_params)
    # After step 1
    elsif params[:job_order].present?
      @job_order = JobOrder.new(job_order_params)
      @job_order.job_statuses << JobStatus.find_by(name: 'Partially created')
      @job_order.user = @user
      @job_order.save
    # Step 0
    else
      @job_order = JobOrder.new
    end

    case @step
    when 1
      render 'job_orders/wizard/order_type'
    when 2
      @job_type = JobType.find(@job_order.job_type_id)
      @service_groups = JobServiceGroup.all.where(job_type: @job_order.job_type)
      render 'job_orders/wizard/service'
    when 3
      @options = JobOption.all.joins(:job_types).where(job_types: {id: @job_order.job_type_id})
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
    params.require(:job_order).permit(:user_id, :job_type_id, :job_service_group_id, :job_service_ids, job_type_id: [], user_files: [])
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
