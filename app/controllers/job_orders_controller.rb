class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[admin settings processed paid picked_up quote_modal timeline_modal quote]
  before_action :set_job_order, only: %w[steps destroy user_approval processed paid picked_up quote_modal timeline_modal quote invoice]
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
          JobOrderMailer.send_job_submitted(@job_order.id).deliver_now
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

  def user_approval
    redirect_link = @job_order.user == @user ? job_orders_path : admin_job_orders_path
    update_status(params[:approved], JobStatus::USER_APPROVAL, JobStatus::WAITING_PROCESSED, true, JobStatus::DECLINED, redirect_link)
  end

  def quote_modal
    render layout: false
  end

  def timeline_modal
    render layout: false
  end

  def quote
    error = false
    if params[:approved].present? && params[:approved] == "true"
      if @job_order.update(job_order_params)
        quote = JobOrderQuote.create(service_fee: params[:service_fee])
        if @job_order.save
          params.permit!
          params.to_h.each do |key, value|
            if key.include?('quote_service_amount_')
              id = +key.delete_prefix("quote_service_amount_").to_i
              JobOrderQuoteService.create!(job_service_id: id, job_order_quote: quote, quantity: value, per_unit: params["quote_service_per_unit_#{id}"]) if params["quote_service_per_unit_#{id}"].present?
            end

            if key.include?('quote_option_amount_')
              id = +key.delete_prefix("quote_option_amount_").to_i
              JobOrderQuoteOption.create!(job_option_id: id, job_order_quote: quote, amount: value)
            end

            unless @job_order.update(job_order_quote: quote)
              error = true
            end
          end

          @job_order.job_order_statuses << JobOrderStatus.create(job_order: @job_order, job_status: JobStatus::USER_APPROVAL) unless error
          unless @job_order.save
            error = true
          end
        else
          error = true
        end
      else
        error = true
      end
    elsif params[:approved].present? &&  params[:approved] == "false"
      @job_order.job_order_statuses << JobOrderStatus.create(job_order: @job_order, job_status: JobStatus::DECLINED)
      unless @job_order.save
        error = true
      end
    else
      error = true
    end

    if !error
      flash[:notice] = "You have updated the Job Order Status to: #{@job_order.job_order_statuses.last.job_status.name}!"
    else
      flash[:alert] = "An error occurred while updating the Job Order Status. Please try again later."
    end
    respond_to do |format|
      format.html { redirect_to admin_job_orders_path }
      format.js { render 'admin_row' }
    end
  end

  def processed
    update_status(params[:processed], JobStatus::WAITING_PROCESSED, JobStatus::PROCESSED, false)
  end

  def paid
    update_status(params[:paid], JobStatus::PROCESSED, JobStatus::PAID, false)
  end

  def picked_up
    update_status(params[:picked_up], JobStatus::PAID, JobStatus::PICKED_UP, false)
  end

  def destroy
    @print_order.destroy
  end

  def admin
    @statuses = [
      {name: "Waiting for Staff Approval", status: JobStatus::STAFF_APPROVAL},
      {name: "Waiting for User Approval", status: JobStatus::USER_APPROVAL},
      {name: "Waiting to be processed", status: JobStatus::WAITING_PROCESSED},
      {name: "Waiting for Payment", status: JobStatus::PROCESSED},
      {name: "Waiting for Pick-Up", status: JobStatus::PAID},
      {name: "Archived", status: JobStatus::PICKED_UP || JobStatus::DECLINED},
    ]

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
    @job_types = JobType.all
  end

  def invoice
    render pdf: 'invoice', template: 'job_orders/invoice.html.erb'
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
    unless @job_order.allow_edit? || @user.admin?
      flash[:alert] = 'You cannot edit this Job Order. Please contact makerspace@uottawa.ca for assistance.'
      redirect_to job_orders_path
    end
  end

  def job_order_params
    params.require(:job_order).permit(:user_id, :job_type_id, :job_service_group_id, :job_service_ids, :comments, :user_comments, :staff_comments, job_service_ids: [], job_type_id: [], user_files: [])
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

  def update_status(param, current_status, true_status, need_false_status, false_status = nil, redirect_link = admin_job_orders_path)
    error = false

    if @job_order.job_order_statuses.last.job_status != current_status
      error = true
    elsif param.present? && param == "true"
      @job_order.job_order_statuses << JobOrderStatus.create(job_order: @job_order, job_status: true_status)
      unless @job_order.save
        error = true
      end
    elsif param.present? && param == "false" && need_false_status
      @job_order.job_order_statuses << JobOrderStatus.create(job_order: @job_order, job_status: false_status)
      unless @job_order.save
        error = true
      end
    else
      error = true
    end

    if !error
      flash[:notice] = "You have updated the Job Order Status to: #{@job_order.job_order_statuses.last.job_status.name}!"
    else
      flash[:alert] = "An error occurred while updating the Job Order Status. Please try again later."
    end
    respond_to do |format|
      format.html { redirect_to redirect_link }
      format.js { render 'admin_row' }
    end
  end

end
