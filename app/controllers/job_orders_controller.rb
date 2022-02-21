class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[admin settings]
  before_action :set_job_order, only: %w[steps destroy]
  before_action :wizard, only: %w[steps]
  before_action :allow_edit, only: %w[steps]

  def index
    @job_orders = []
    @archived_job_orders = []
    @drafts = []
    @user.job_orders.each do |jo|
      if jo.job_order_statuses.last.job_status == JobStatus::DRAFT
        @drafts << jo
      elsif jo.job_order_statuses.last.job_status == JobStatus::DECLINED || jo.job_order_statuses.last.job_status == JobStatus::PICKED_UP
        @archived_job_orders << jo
      else
        @job_orders << jo
      end
    end
  end

  def new
    @job_order = JobOrder.new
  end

  def steps
    error = false

    if @job_order.present? && @job_order.user == @user

      if params[:keep_files].present?
        (@job_order.user_files.pluck(:id) - params[:keep_files].map(&:to_i)).each do |file_id|
          @job_order.user_files.find(file_id).purge
        end
      end

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
      @step = @job_order.max_step if (@job_order.max_step < @step)
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
      when 5
        if @job_order.job_order_statuses.last.job_status != JobStatus::STAFF_APPROVAL
          @job_order.job_order_statuses << JobOrderStatus.create!(job_order: @job_order, job_status: JobStatus::STAFF_APPROVAL)
          flash[:notice] = "Your job order has been submitted for staff approval!"
        else
          flash[:notice] = "Your job order has been updated!"
        end
        redirect_to job_orders_path
      else
        redirect_to job_orders_path
      end
    end
  end

  def create
    @job_order = JobOrder.new(job_order_params)
    @job_order.user = @user
    if @job_order.save
      @job_order.job_order_statuses << JobOrderStatus.create(job_order: @job_order, job_status: JobStatus::DRAFT)
      if @job_order.save
        redirect_to job_order_steps_path(job_order_id: @job_order.id, step: 2)
      else
        @job_order.destroy
        redirect_to new_job_orders_path
      end
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
    if params[:query_date].present?
      session[:query_date] = params[:query_date].to_i
    end

    if !session[:query_date].present? || session[:query_date] == 0
      session[:query_date] = 0
      @job_orders = JobOrder.all.without_drafts
    else
      @job_orders = JobOrder.all.without_drafts.where(created_at: session[:query_date].days.ago..)
    end
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
    @job_order.allow_edit? || @user.admin?
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
    @step = params[:step].present? ? params[:step].to_i : 1
  end

end
