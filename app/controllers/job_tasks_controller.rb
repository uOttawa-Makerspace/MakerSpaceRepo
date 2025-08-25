class JobTasksController < ApplicationController
  before_action :set_job_order_and_task, except: [:create]

  def destroy
    @job_task.destroy
    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order), notice: 'Task was successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def create
    @job_order = JobOrder.find(params[:job_order_id])

    highest_numbered_task = @job_order.job_tasks.maximum("CAST(SUBSTRING(title FROM 'Task ([0-9]+)') AS INTEGER)") || 0
    total_tasks_count = @job_order.job_tasks.count
    next_task_number = [highest_numbered_task, total_tasks_count].max + 1

    @job_task = @job_order.job_tasks.create!(
      title: "Task ##{next_task_number}"
    )
    
    redirect_to edit_job_order_job_task_path(@job_order, @job_task, step: 1)
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = "Failed to create task: #{e.message}"
    redirect_to job_order_path(@job_order)
  end

  def edit
    @step = params[:step].to_i

    if @job_task.job_type&.name == "Design Services"
      @job_type = JobType.find(@job_task.job_type_id)
      @service_groups = JobServiceGroup.not_deleted.where(job_type: @job_type).order(:id)
      return render "job_orders/wizard/service"
    end

    case @step
    when 1
      render "job_orders/wizard/order_type"
    when 2
      @job_type = JobType.find(@job_task.job_type_id)
      @service_groups = JobServiceGroup.not_deleted.where(job_type: @job_type).order(:id)
      render "job_orders/wizard/service"
    when 3
      @options = JobOption
        .joins(:job_types)
        .where(job_types: { id: @job_task.job_type_id })
        .where("job_options.is_deleted = FALSE OR job_options.id IN (?)", 
              @job_task.job_task_options.pluck(:job_option_id))
      render "job_orders/wizard/options"
    when 4
      render "job_orders/wizard/submission"
    else
      redirect_to job_order_path(@job_order)
    end
  end

  def update
    unless @job_order.user == current_user || current_user.admin?
      redirect_to job_orders_path, alert: t("job_orders.alerts.job_order_not_found")
      return
    end

    if params[:comments].present?
      @job_order.chat_messages.create(
        message: params[:comments],
        sender: current_user
      )
    end

    # Handle custom service if selected
    if params[:job_task] && params[:job_task][:job_service_id] == "custom"
      service_group_id = nil
      custom_service_name = nil

      params.each do |key, value|
        next unless key.start_with?('job_service_name_') && value.present?
        service_group_id = key.split('_').last.to_i
        custom_service_name = value
        break
      end

      if service_group_id && custom_service_name.present?
        custom_service = @job_order.job_services.find_or_initialize_by(
          user_created: true,
          job_service_group_id: service_group_id
        )
        custom_service.name = custom_service_name
        custom_service.save!

        params[:job_task][:job_service_id] = custom_service.id.to_s
      end
    end

    submitted_options = if job_task_params.present? && job_task_params[:job_task_options_attributes].present?
      Array(job_task_params[:job_task_options_attributes]).each_with_object({}) do |opt, hash|
        next if opt[:_destroy] == "1"
        hash[opt[:job_option_id].to_i] = opt
      end
    else
      {}
    end

    # Update or create options
    submitted_options.each do |job_option_id, attrs|
      @job_task.job_task_options
              .find_or_initialize_by(job_option_id: job_option_id)
              .update(attrs.except(:_destroy, :id))
    end

    # Remove options that weren't submitted (if on that step of form)
    if params[:step].to_i == 3
      @job_task.job_task_options.where.not(job_option_id: submitted_options.keys).destroy_all

      # Also remove quoted options if the option is deselected
      if @job_task.job_task_quote
        @job_task.job_task_quote.job_task_quote_options.where.not(job_option_id: submitted_options.keys).destroy_all
      end
    end

    # Handle rest
    if job_task_params.present? && !@job_task.update(job_task_params.except(:job_task_options_attributes))
        flash[:alert] = @job_task.errors.full_messages.to_sentence
        return redirect_back(fallback_location: edit_job_order_job_task_path(@job_order, @job_task, 
step: params[:step]))
    end

    # Don't do default next step behaviour for oddball cases
    if params[:add_another].present? && params[:add_another] == "true" 
      highest_numbered_task = @job_order.job_tasks.maximum("CAST(SUBSTRING(title FROM 'Task ([0-9]+)') AS INTEGER)") || 0
      total_tasks_count = @job_order.job_tasks.count
      next_task_number = [highest_numbered_task, total_tasks_count].max + 1

      @job_task = @job_order.job_tasks.create!(
        title: "Task ##{next_task_number}"
      )
      
      return redirect_to edit_job_order_job_task_path(@job_order, @job_task, step: 1)
    end
    return redirect_to job_order_path(@job_order) if params[:save_draft].present? && params[:save_draft] == "true" 
    if @job_task.job_type&.name == "Design Services"
      submit_for_approval
      return redirect_to job_order_path(@job_order)
    end  

    next_step = params[:step].to_i + 1
    if next_step >= 5
      submit_for_approval
      redirect_to job_order_path(@job_order)
    else
      redirect_to edit_job_order_job_task_path(@job_order, @job_task, step: next_step)
    end
  end

  private

  def job_task_params
    params.require(:job_task).permit(
      :job_type_id,
      :comments,
      :job_service_id,
      job_task_options_attributes: [:id, :job_option_id, :option_file, :_destroy],
      user_files: [],
      staff_files: []
    )
  rescue ActionController::ParameterMissing
    {}
  end

  def submit_for_approval
    return if @job_order.job_order_statuses.last&.job_status != JobStatus::DRAFT

    @job_order.job_order_statuses.create!(
      job_status: JobStatus::STAFF_APPROVAL,
      user: current_user
    )
    JobOrderMailer.send_job_submitted(@job_order.id).deliver_now
    flash[:notice] = t("job_orders.alerts.job_order_submitted_for_approval")
  end

  def set_job_order_and_task
    @job_order = JobOrder.find(params[:job_order_id])
    @job_task = @job_order.job_tasks.find(params[:id])
  end
end