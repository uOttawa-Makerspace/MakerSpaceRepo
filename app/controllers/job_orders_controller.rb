class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[index new steps edit create update destroy]
  before_action :set_job_order, only: %w[steps edit destroy]
  before_action :wizard, only: %w[steps]
  before_action :allow_edit, only: %w[steps]

  # Statuses for DB
  $statuses = {
    'draft' => 'Draft',
    'staff_approval' => 'Waiting for Staff Approval',
    'user_approval' => 'Waiting for User Approval',
    'waiting_processed' => 'Waiting to be Processed',
    'processed' => 'Processed',
    'paid' => 'Paid',
    'picked_up' => 'Picked-Up',
    'declined' => 'Declined',
  }

  def index
    @job_orders = @user.job_orders
  end

  def new
    @job_order = JobOrder.new
  end

  def steps
    error = false

    if @job_order.present? && @job_order.user == @user

      if params[:job_order].present?

        if params[:job_service_name].present?
          @job_order.job_services << JobService.create!(name: params[:job_service_name], job_service_group_id: params[:job_order][:job_service_group_id], user_created: true, job_order_id: @job_order.id)
        end

        unless @job_order.update(job_order_params)
          error = true
        end
      end

      unless @job_order.add_options(params)
        error = true
      end
    else
      error = true
    end

    if error
      redirect_to job_order_steps_path(@job_order, step: (params[:step].to_i - 1))
      flash[:alert] = "An error occurred while saving the job order step. make sure that you uploaded the right file types. Please try again."
    else
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
      else
        redirect_to job_orders_path
      end
    end
  end

  def create
    @job_order = JobOrder.new(job_order_params)
    @job_order.user = @user
    @job_order.job_statuses << JobStatus.find_by(name: $statuses['draft'])
    if @job_order.save
      redirect_to job_order_steps_path(job_order_id: @job_order.id, step: 2)
    else
      flash[:alert] = 'An error occurred while trying to create the job order. Please try again.'
      render 'new'
    end
  end

  def update

  end

  def destroy
    @print_order.destroy
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

  def set_job_order
    if JobOrder.where(id: params[:job_order_id]).present?
      jo = JobOrder.find(params[:job_order_id])
      if @user.admin? || @user.id == jo.user_id
        @job_order = jo
      else
        flash[:alert] = 'You do not have permission to view this job order.'
        redirect_to new_job_orders_path
      end
    else
      flash[:alert] = 'You do not have permission to view this job order.'
      redirect_to new_job_orders_path
    end

  end

  def allow_edit
    @job_order.status.last == 'Draft'
  end

  def job_order_params
    params.require(:job_order).permit(:user_id, :job_type_id, :job_service_group_id, :job_service_ids, :comments, job_service_ids: [], job_type_id: [], user_files: [])
  end

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = 'You cannot access this area.'
      redirect_to root_path
    end
  end

  def wizard
    @step = params[:step].to_i
    @step ||= 1
    @step = @job_order.max_step if (@job_order.max_step < @step)
    puts @step
  end

end
