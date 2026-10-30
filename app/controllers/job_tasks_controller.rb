class JobTasksController < SessionsController
  before_action :signed_in
  before_action :set_job_order_and_task, except: [:create]
  before_action :set_job_order, only: [:create]
  before_action :authorize_order!, only: [:edit]
  before_action :authorize_order_owner!, except: [:edit]

  # create, update and destroy are the customer-side writers of the order's tasks, options, files and services.
  # Each runs its writes inside JobOrder#apply_owner_change! (JOB-01): row lock, the status rule, and a quoted
  # order goes back to staff with its invoice voided.
  def destroy
    outcome = apply_change { @job_task.destroy! }
    return unless outcome

    respond_to do |format|
      format.html do
        flash[:notice] = 'Task was successfully deleted.' unless outcome == :sent_back
        redirect_to job_order_path(@job_order)
      end
      format.json { head :no_content }
    end
  end

  def create
    return unless apply_change { @job_task = create_next_task! }

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
    return unless apply_change { apply_task_update! }

    # The wizard's comments are posted to the order chat once the change has committed.
    @job_order.chat_messages.create(message: params[:comments], sender: current_user) if params[:comments].present?

    # Don't do default next step behaviour for oddball cases
    return redirect_to edit_job_order_job_task_path(@job_order, @job_task, step: 1) if params[:add_another] == "true"
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
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = e.record.errors.full_messages.to_sentence
    redirect_back(fallback_location: edit_job_order_job_task_path(@job_order, @job_task, step: params[:step]))
  end

  private

  # Runs the block through JobOrder#apply_owner_change!. Returns :applied or :sent_back (with the "sent back for a
  # new quote" notice) when the change committed; otherwise redirects with the reason and returns false.
  def apply_change(&)
    return :applied unless @job_order.apply_owner_change!(actor: current_user, &)

    flash[:notice] = t("job_orders.alerts.order_sent_back_for_requote")
    :sent_back
  rescue JobOrder::OwnerChangeRefused
    refuse_change(t("job_orders.alerts.paid_order_cannot_change"))
  rescue JobOrder::StaleDraftOrderError => e
    Rails.logger.error("[job_tasks] change to job order ##{@job_order.id} refused: #{e.message}")
    refuse_change(t("job_orders.alerts.owner_change_draft_order_failed"))
  end

  def refuse_change(message)
    respond_to do |format|
      format.html do
        flash[:alert] = message
        redirect_to job_order_path(@job_order)
      end
      format.any { head :conflict }
    end
    false
  end

  def create_next_task!
    highest_numbered_task = @job_order.job_tasks.maximum("CAST(SUBSTRING(title FROM 'Task ([0-9]+)') AS INTEGER)") || 0
    next_task_number = [highest_numbered_task, @job_order.job_tasks.count].max + 1
    @job_order.job_tasks.create!(title: "Task ##{next_task_number}")
  end

  # The wizard step's writes. Raises ActiveRecord::RecordInvalid (rolling the whole step back) when the task or a
  # custom service does not validate.
  def apply_task_update!
    use_custom_service! if params[:job_task] && params[:job_task][:job_service_id] == "custom"

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

    @job_task.update!(job_task_params.except(:job_task_options_attributes)) if job_task_params.present?
    @job_task = create_next_task! if params[:add_another] == "true"
  end

  # Handle custom service if selected
  def use_custom_service!
    service_group_id = nil
    custom_service_name = nil

    params.each do |key, value|
      next unless key.start_with?('job_service_name_') && value.present?
      service_group_id = key.split('_').last.to_i
      custom_service_name = value
      break
    end

    return unless service_group_id && custom_service_name.present?

    custom_service = @job_order.job_services.find_or_initialize_by(
      user_created: true,
      job_service_group_id: service_group_id
    )
    custom_service.name = custom_service_name
    custom_service.save!

    params[:job_task][:job_service_id] = custom_service.id.to_s
  end

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

    @tasks_missing_information = @job_order.job_tasks.select do |task|
      task.job_type.blank? ||
        (task.job_type.job_service_groups.any? && task.job_service.blank?)
    end
    return if @tasks_missing_information.any?

    @job_order.job_order_statuses.create!(
      job_status: JobStatus::STAFF_APPROVAL,
      user: current_user
    )
    JobOrderMailer.send_job_submitted(@job_order.id).deliver_now
    flash[:notice] = t("job_orders.alerts.job_order_submitted_for_approval")
  end

  def set_job_order
    @job_order = JobOrder.not_deleted.find(params[:job_order_id])
  end

  def set_job_order_and_task
    set_job_order
    @job_task = @job_order.job_tasks.find(params[:id])
  end

  # Creating, changing and deleting tasks is for the order's owner or an admin
  # (the same rule the order page uses to show the task buttons).
  def authorize_order_owner!
    return if current_user.admin? || current_user.id == @job_order.user_id

    flash[:alert] = t("job_orders.alerts.no_permission")
    redirect_to new_job_orders_path
  end

  # Viewing the wizard: same audience as JobOrdersController#set_job_order,
  # owner, staff or admin.
  def authorize_order!
    return if current_user.admin? || current_user.staff? || current_user.id == @job_order.user_id

    flash[:alert] = t("job_orders.alerts.no_permission")
    redirect_to new_job_orders_path
  end
end