class JobOrdersController < SessionsController
  before_action :no_container, only: :landing

  before_action :current_user
  before_action :signed_in,
                except: %i[
                  user_magic_approval
                  user_magic_approval_confirmation
                  pay
                  stripe_success
                  stripe_cancelled
                  landing
                ]
  before_action :grant_access,
                only: %w[
                  admin
                  settings
                  start_processing
                  processed
                  paid
                  picked_up
                  quote_modal
                  timeline_modal
                  decline_modal
                  completed_email_modal
                  comments_modal
                  quote
                  resend_quote_email
                  comments
                ]
  before_action :set_job_order,
                only: %w[
                  destroy
                  user_approval
                  start_processing
                  processed
                  paid
                  picked_up
                  quote_modal
                  timeline_modal
                  decline_modal
                  completed_email_modal
                  comments_modal
                  quote
                  invoice
                  resend_quote_email
                  comments
                ]

  def index
    @job_orders = []
    @archived_job_orders = []
    @drafts = []
    @user.job_orders.not_deleted.each do |jo|
      next unless jo.job_order_statuses.last

      if jo.job_order_statuses.last.job_status == JobStatus::DRAFT
        @drafts << jo
      else
        @job_orders << jo
      end
    end
  end

  def show
    @job_order = JobOrder.find_by(id: params[:id], is_deleted: false)
    @staff = User.staff
    @message =
      JobOrderMessage.find_by(name: "processed").retrieve_message(@job_order.id)

    if @job_order.nil?
      flash[:alert] = t("job_orders.alerts.job_order_not_found")
      return redirect_to job_orders_path     
    end
    
    if current_user.id == @job_order.user_id
      @unread_messages = @job_order.chat_messages.unread(current_user)
      @unread_messages.update_all(is_read: true) # rubocop:disable Rails/SkipsModelValidations
    end

    flash[:notice] = t("job_orders.alerts.action_required_scroll_to_timeline") if [JobStatus::USER_APPROVAL, 
JobStatus::SENT_REMINDER, JobStatus::COMPLETED].include?(@job_order.job_order_statuses.last&.job_status) && @job_order.user_id == current_user.id

    @tasks_missing_information = @job_order.job_tasks.select do |task|
      task.job_type.blank? || (task.job_type.name != "Design Services" && task.job_service.blank?)
    end
    flash[:alert] = 
"#{t('job_orders.alerts.missing_info')} #{@tasks_missing_information.map(&:title).join(', ')}" if @tasks_missing_information.any? 
  end

  def new
    @job_order = JobOrder.new
  end

  def create
    @job_order = JobOrder.new(job_order_params)
    @job_order.user = @user

    if @job_order.save
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: JobStatus::DRAFT,
        user: @user
      )

      if @job_order.save
        @job_task = @job_order.job_tasks.create!(
          title: "Task #1",
          # Force job_type_id = 3 if it's the "Need Design Help" flow
          job_type: params[:redirect_step].to_i == 2 ? JobType.where(name: "Design Services").first : nil
        )
        
        redirect_to edit_job_order_job_task_path(@job_order, @job_task, step: 1)
      else
        @job_order.update(is_deleted: true)
        redirect_to new_job_orders_path
      end
    else
      flash[:alert] = t("job_orders.alerts.error_while_trying_to_create")
      render "new"
    end
  end

  def user_magic_approval
    @token = params[:token]
    verifier = Rails.application.message_verifier(:job_order_id)
    if verifier.valid_message?(@token) &&
         JobOrder.where(
           id: verifier.verify(@token),
           is_deleted: false
         ).present? &&
         [JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER].include?(
           JobOrder
             .where(id: verifier.verify(@token), is_deleted: false)
             .first
             .job_order_statuses
             .last
             .job_status
         )
      @job_order =
        JobOrder.where(id: verifier.verify(@token), is_deleted: false).first
      render "job_orders/magic_approval"
    else
      flash[:alert] = t("job_orders.alerts.approval_magic_link_expired")
      redirect_to job_orders_path
    end
  end

  def user_magic_approval_confirmation
    @token = params[:token]
    verifier = Rails.application.message_verifier(:job_order_id)
    if verifier.valid_message?(params[:token])
      @job_order =
        JobOrder.where(id: verifier.verify(@token), is_deleted: false).first
      @status = if update_status(
           params[:approved],
           [JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER],
           JobStatus::WAITING_PROCESSED,
           true,
           JobStatus::DECLINED,
           nil
         )
        true
      else
        false
      end
      render "job_orders/magic_approval_confirmation"
    else
      flash[:alert] = t("job_orders.alerts.error_accept_deny_order")
      redirect_to job_orders_path
    end
  end

  def user_approval
    if update_status(
         params[:approved],
         [JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER],
         JobStatus::WAITING_PROCESSED,
         true,
         JobStatus::DECLINED,
         nil
       ) && params[:approved] == "true"
      JobOrderMailer.send_job_user_approval(@job_order.id).deliver_now
    end

    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
      format.js { render "admin_row" }
    end
  end

  def quote_modal
    render layout: false
  end

  def timeline_modal
    render layout: false
  end

  def decline_modal
    render layout: false
  end

  def comments_modal
    render layout: false
  end

  def quote
    error = false

    return flash[:alert] = t("job_orders.alerts.error_while_updating") if params[:approved].blank?

    if params[:approved].present? && params[:approved] == "true"
      # ACCEPT JOB
      JobOrder.transaction do
        @job_order.job_tasks.each do |task|
          price_key = "job_task_quote_price_#{task.id}"
          job_task_quote = task.job_task_quote || task.build_job_task_quote
          job_task_quote.price = params[price_key].presence || 0.0
          
          # Service
          qty_key   = "task_#{task.id}_service_qty"
          svc_price_key = "task_#{task.id}_service_price"
          
          job_task_quote.service_quantity = params[qty_key].presence || 0.0
          job_task_quote.service_price = params[svc_price_key].presence || 0.0

          job_task_quote.save!

          # Options
          task.job_task_options.each do |option|
            opt_key = "task_#{task.id}_option_price_#{option.job_option_id}"
            next if params[opt_key].blank?

            qt_option = job_task_quote.job_task_quote_options.find_or_initialize_by(job_option_id: option.job_option_id)
            qt_option.price = params[opt_key]
            qt_option.save!
          end

          file_key = "task_#{task.id}_staff_files"
          next if params[file_key].blank?
          params[file_key].each do |file|
            task.staff_files.attach(file)
          end
        end

        # line items
        if params[:job_quote_line_items].present?
          @job_order.job_quote_line_items.destroy_all

          params[:job_quote_line_items].each_value do |item_params|
            desc = item_params[:description].to_s.strip
            price = item_params[:price].to_s.strip

            next if desc.blank? && price.blank?

            @job_order.job_quote_line_items.create!(
              description: desc,
              price: price.presence || 0.0
            )
          end
        end

        if params[:user_comments].present?
          @job_order.chat_messages.create(
            message: params[:user_comments],
            sender: current_user
          )
        end

        @job_order.staff_comments = params[:job_order][:staff_comments] if params[:job_order][:staff_comments].present?

        @job_order.job_order_statuses << JobOrderStatus.create(
          job_order: @job_order,
          job_status: JobStatus::USER_APPROVAL,
          user: @user
        )

        if @job_order.save
          JobOrderMailer.send_job_quote(@job_order.id).deliver_now
        else
          error = true
        end
      end
    elsif params[:approved] == "false"
      # DELCINE JOB
      if params[:user_comments].present?
        @job_order.chat_messages.create(
          message: params[:user_comments],
          sender: current_user
        )
      end

      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: JobStatus::DECLINED,
        user: @user
      )

      if @job_order.save
        JobOrderMailer.send_job_declined(@job_order.id).deliver_now
      else
        error = true
      end
    else
      error = true
    end

    if !error
      flash[:notice] = t(
        "job_orders.alerts.updated_job_status_to_x",
        status: @job_order.job_order_statuses.last.job_status.t_name
      )
    else
      flash[:alert] = t("job_orders.alerts.error_while_updating")
    end
    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
    end
  end

  def comments
    @job_order.update(job_order_params)
    if @job_order.save
      flash[:notice] = t("job_orders.alerts.updated_successfully")
    else
      flash[:alert] = t("job_orders.alerts.error_while_updating")
    end

    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
    end
  end

  def start_processing
    update_status(
      params[:start_processing],
      JobStatus::WAITING_PROCESSED,
      JobStatus::BEING_PROCESSED,
      false
    )
  end

  def processed
    if update_status(
         params[:completed],
         JobStatus::BEING_PROCESSED,
         JobStatus::COMPLETED,
         false,
         nil,
         nil
       ) && params[:completed] == "true"
      # Bypass Payment if order is 0$
      if @job_order.total_price === 0
        @job_order.job_order_statuses << JobOrderStatus.create(
          job_order: @job_order,
          job_status: JobStatus::PAID,
          user: @user
        )
        JobOrderMailer.payment_succeeded(@job_order.id).deliver_now
      elsif params[:send_email].present? && params[:send_email] == "true"
        JobOrderMailer.send_job_completed(
          @job_order.id,
          params[:message]
        ).deliver_now
      end
    end

    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
      format.js { render "admin_row" }
    end
  end

  def paid
    update_status(params[:paid], JobStatus::COMPLETED, JobStatus::PAID, false)
  end

  def picked_up
    update_status(
      params[:picked_up],
      JobStatus::PAID,
      JobStatus::PICKED_UP,
      false
    )
  end

  def resend_quote_email
    @job_order.job_order_statuses << JobOrderStatus.create(
      job_order: @job_order,
      job_status: JobStatus::SENT_REMINDER,
      user: @user
    )
    JobOrderMailer.send_job_quote(@job_order.id, true).deliver_now if @job_order.save
    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
      format.js { render "admin_row" }
    end
  end

  def destroy
    @job_order.update(is_deleted: true)
    if @user.admin?
      redirect_to admin_job_orders_path
    else
      redirect_to job_orders_path
    end

    flash[:notice] = "Job order deleted successfully."
  end

  def assign_staff
    @job_order = JobOrder.find_by(id: params[:job_order_id], is_deleted: false)
    if @job_order.present? && (@user.admin? || @user.id == params[:staff_id].to_i)
      @job_order.assigned_staff_id = params[:staff_id]
      if @job_order.save
        flash[:notice] = "#{@job_order.assigned_staff&.name || "No staff"} has been assigned to this job order."

        if @job_order.assigned_staff.present? && @user.admin? && @job_order.assigned_staff != @user
          JobOrderMailer.staff_assigned(@job_order.id, @job_order.assigned_staff.id).deliver_later
        end
      else
        flash[:alert] = "#{@job_order.assigned_staff.name} could not be assigned to this job order."
      end
    else
      flash[:alert] = "#{@job_order.assigned_staff.name} could not be assigned to this job order."
    end
    redirect_back(fallback_location: job_orders_path)
  end

  def admin
    @staff = User.staff

    # get all stuff for filtering
    @statuses = JobStatus.where.not(name: "Draft")
    @job_types = JobType.all

    @job_orders = JobOrder.all.not_deleted.without_drafts.includes(:job_services).order(created_at: :desc)
  end

  def settings
    @service_groups = JobServiceGroup.not_deleted.order(:job_type_id)
    @services = JobService.not_deleted.not_user_created.order(:job_service_group_id)
    @options = JobOption.not_deleted
    @job_types = JobType.all
  end

  def invoice
    render layout: false
  end

  def pay
    @token = params[:token]
    verifier = Rails.application.message_verifier(:job_order_id)
    if verifier.valid_message?(@token) &&
         JobOrder.where(
           id: verifier.verify(@token),
           is_deleted: false
         ).present? &&
         JobStatus::COMPLETED ==
           JobOrder
             .where(id: verifier.verify(@token), is_deleted: false)
             .first
             .job_order_statuses
             .last
             .job_status
      @job_order =
        JobOrder.where(id: verifier.verify(@token), is_deleted: false).first
      @payment_link = @job_order.checkout_link
      render "job_orders/pay"
    else
      flash[:alert] = t("job_orders.alerts.pay_magic_link_expired")
      redirect_to job_order_path(@job_order.id)
    end
  end

  def stripe_success
  end

  def stripe_cancelled
  end

  def landing
    render layout: "application"
  end

  private

  def set_job_order
    if JobOrder.where(id: params[:job_order_id], is_deleted: false).present? ||
         JobOrder.where(id: params[:id], is_deleted: false).present?
      jo =
        JobOrder.where(
          id:
            
              params[:job_order_id].presence || params[:id],
          is_deleted: false
        ).first
      if @user.admin? | @user.staff? || @user.id == jo.user_id
        @job_order = jo
      else
        flash[:alert] = t("job_orders.alerts.no_permission")
        redirect_to new_job_orders_path
      end
    else
      flash[:alert] = t("job_orders.alerts.no_permission")
      redirect_to new_job_orders_path
    end
  end

  def job_order_params
    params.require(:job_order).permit(
      :user_id,
      :job_type_id,
      :job_service_group_id,
      :job_service_ids,
      :comments,
      :user_comments,
      :staff_comments,
      job_service_ids: [],
      job_type_id: [],
      user_files: [],
      staff_files: []
    )
  end

  def grant_access
    return if current_user.staff? || current_user.admin?
      flash[:alert] = t("job_orders.alerts.cannot_access_area")
      redirect_to root_path
    
  end

  def update_status(
    param,
    current_status,
    true_status,
    need_false_status,
    false_status = nil,
    redirect_link = job_order_path(@job_order.id)
  )
    error = false

    if if current_status.is_a?(Array)
         !current_status.include?(@job_order.job_order_statuses.last.job_status)
       else
         @job_order.job_order_statuses.last.job_status != current_status
       end
      error = true
    elsif param.present? && param == "true"
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: true_status,
        user: @user
      )
      error = true unless @job_order.save
    elsif param.present? && param == "false" && need_false_status
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: false_status,
        user: @user
      )
      error = true unless @job_order.save
    else
      error = true
    end

    if !error
      flash[:notice] = t(
        "job_orders.alerts.updated_job_status_to_x",
        status: @job_order.job_order_statuses.last.job_status.t_name
      )
    else
      flash[:alert] = t("job_orders.alerts.error_while_updating")
    end

    if redirect_link.nil?
      !error
    else
      respond_to do |format|
        format.html { redirect_to redirect_link }
        format.js { render "admin_row" }
      end
    end
  end
end
