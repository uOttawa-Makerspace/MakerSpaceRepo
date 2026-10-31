class JobOrdersController < SessionsController
  before_action :no_container, only: :landing

  before_action :current_user
  before_action :signed_in,
                except: %i[
                  user_magic_approval
                  user_magic_approval_confirmation
                  pay
                  landing
                ]
  before_action :grant_access,
                only: %w[
                  assign_staff
                  admin
                  settings
                  start_processing
                  processed
                  paid
                  picked_up
                  timeline_modal
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
                  timeline_modal
                  quote
                  invoice
                  resend_quote_email
                  comments
                ]

  def index
    @job_orders = []
    @archived_job_orders = []
    @drafts = []
    @user.job_orders.not_deleted.includes(job_order_statuses: :job_status).each do |jo|
      next unless jo.latest_status

      if jo.latest_status.job_status == JobStatus.draft
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
    
    unless current_user.admin? || current_user.staff? || current_user.id == @job_order.user_id
      flash[:alert] = t("job_orders.alerts.no_permission")
      return redirect_to new_job_orders_path
    end

    if current_user.id == @job_order.user_id
      @unread_messages = @job_order.chat_messages.unread(current_user)
      @unread_messages.update_all(is_read: true) # rubocop:disable Rails/SkipsModelValidations
    end

    flash.now[:notice] = t("job_orders.alerts.action_required_scroll_to_timeline") if [JobStatus.user_approval, 
JobStatus.sent_reminder, JobStatus.completed].include?(@job_order.latest_status&.job_status) && @job_order.user_id == current_user.id

    @tasks_missing_information = @job_order.job_tasks.select do |task|
      # job type is missing or job type has a service not chosen
      task.job_type.blank? || (task.job_type.job_service_groups.any? && task.job_service.blank?)
    end
    flash.now[:alert] =
"#{t('job_orders.alerts.missing_info')} #{@tasks_missing_information.map(&:title).join(', ')}" if @tasks_missing_information.any? 
  end

  def new
    @job_order = JobOrder.new
  end

  def create
    @job_order = JobOrder.new(job_order_create_params)
    @job_order.user = @user

    if @job_order.save
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: JobStatus.draft,
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
    @job_order = JobOrder.from_approval_token(@token)
    if @job_order &&
         [JobStatus.user_approval, JobStatus.sent_reminder].include?(
           @job_order.latest_status.job_status
         )
      render "job_orders/magic_approval"
    else
      flash[:alert] = t("job_orders.alerts.approval_magic_link_expired")
      redirect_to job_orders_path
    end
  end

  def user_magic_approval_confirmation
    @token = params[:token]
    @job_order = JobOrder.from_approval_token(@token)
    if @job_order
      @status = if update_status(
           params[:approved],
           [JobStatus.user_approval, JobStatus.sent_reminder],
           JobStatus.waiting_processed,
           true,
           JobStatus.declined,
           nil,
           actor: @job_order.user,
           approval_token: @token
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
         [JobStatus.user_approval, JobStatus.sent_reminder],
         JobStatus.waiting_processed,
         true,
         JobStatus.declined,
         nil
       ) && params[:approved] == "true"
      JobOrderMailer.send_job_user_approval(@job_order.id).deliver_now
    end

    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
      format.js { render "admin_row" }
    end
  end

  # One query for the rows and their statuses, one for the users of the rows that name their actor
  # (JobOrderStatus#actor_shown?); no per-row lookups.
  def timeline_modal
    @statuses = @job_order.job_order_statuses.includes(:job_status).reorder(id: :desc).to_a
    ActiveRecord::Associations::Preloader.new(records: @statuses.select(&:actor_shown?), associations: :user).call
    render layout: false
  end

  def quote
    error = false
    mail_failed = false

    return flash[:alert] = t("job_orders.alerts.error_while_updating") if params[:approved].blank?

    if params[:approved] == "true"
      # ACCEPT JOB. The prices and the new status are one transition: its own transaction, row lock first
      # (concurrent re-quotes serialize; the status is read under the lock, and a paid order is refused there,
      # JOB-04), the new quote's draft rule voiding any live Shopify draft (fail closed: if it cannot be deleted
      # nothing is written: no price, status or email). A refusal is reported by the model, once.
      result = @job_order.transition!(from: JobOrder.quotable_statuses, to: JobStatus.user_approval,
                                      actor: @user) { apply_quote_params! }
      unless result.ok?
        flash[:alert] = refusal_alert(result, requote: true)
        return redirect_to job_order_path(@job_order.id)
      end
      # After the commit: the chat message's notification must not be enqueued by a quote that is rolled back, and
      # a mail failure must not roll back a quote whose old Shopify draft is already deleted (the restored id would
      # point at a deleted draft). Staff can use resend_quote_email.
      post_user_comment
      begin
        JobOrderMailer.send_job_quote(@job_order.id).deliver_now
      rescue StandardError => e
        Rails.logger.error("[job_orders#quote] quote email for ##{@job_order.id} failed: #{e.class}: #{e.message}")
        mail_failed = true
      end
    elsif params[:approved] == "false"
      # DECLINE JOB. JOB-04: never once paid (transition! reads the status under the row lock).
      declined = @job_order.transition!(from: JobOrder.quotable_statuses, to: JobStatus.declined, actor: @user)

      if declined.ok?
        post_user_comment
        JobOrderMailer.send_job_declined(@job_order.id).deliver_now
      else
        flash[:alert] = refusal_alert(declined)
        return redirect_to job_order_path(@job_order.id)
      end
    else
      error = true
    end

    if mail_failed
      flash[:alert] = t("job_orders.alerts.quote_saved_email_failed")
    elsif !error
      flash[:notice] = t(
        "job_orders.alerts.updated_job_status_to_x",
        status: @job_order.latest_status.job_status.t_name
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
      JobStatus.waiting_processed,
      JobStatus.being_processed,
      false
    )
  end

  def processed
    if update_status(
         params[:completed],
         JobStatus.being_processed,
         JobStatus.completed,
         false,
         nil,
         nil
       ) && params[:completed] == "true"
      # Bypass Payment if order is 0$ (through the same transition rule as any other payment)
      if @job_order.total_price.zero?
        paid = @job_order.transition!(from: JobStatus.completed, to: JobStatus.paid, actor: @user)
        if paid.ok?
          flash[:notice] = t("job_orders.alerts.updated_job_status_to_x", status: JobStatus.paid.t_name)
          JobOrderMailer.payment_succeeded(@job_order.id).deliver_now
        else
          # the order is Completed but not Paid: say so, and no "updated" notice that would suggest otherwise
          flash.delete(:notice)
          flash[:alert] = t(paid.zero_order_message_key)
        end
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
    update_status(params[:paid], JobStatus.completed, JobStatus.paid, false)
  end

  def picked_up
    update_status(
      params[:picked_up],
      JobStatus.paid,
      JobStatus.picked_up,
      false
    )
  end

  # Only while the customer has a live quote: a reminder re-issues the approve link, so one for an order that went
  # back to staff (or moved on) would make an unquoted or spent quote approvable again.
  def resend_quote_email
    sent = @job_order.transition!(from: [JobStatus.user_approval, JobStatus.sent_reminder],
                                  to: JobStatus.sent_reminder, actor: @user)
    if sent.ok?
      JobOrderMailer.send_job_quote(@job_order.id, true).deliver_now
    else
      flash[:alert] = t(sent.message_key)
    end
    respond_to do |format|
      format.html { redirect_to job_order_path(@job_order.id) }
      format.js { render "admin_row" }
    end
  end

  def destroy
    # One locked operation: the order's Shopify draft (a payable invoice) is settled with the delete, fail closed.
    result = @job_order.soft_delete!(actor: @user)
    if result.ok?
      flash[:notice] = "Job order deleted successfully."
      redirect_to orders_list_path
    else
      flash[:alert] = t(result.message_key("job_orders.alerts.delete_refused", reasons: JobOrder::TransitionResult::DELETE_REASONS))
      # a deleted order has no page to show the message on (set_job_order would replace it)
      redirect_to(result.reason == :order_missing ? orders_list_path : job_order_path(@job_order.id))
    end
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

    @job_orders = JobOrder.all.not_deleted.without_drafts.includes(:job_services, job_order_statuses: :job_status).order(created_at: :desc)
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
    @job_order = JobOrder.from_pay_token(@token)
    if @job_order.nil?
      # expired, tampered, deleted-order, already-retired or pre-D-J11 links
      flash[:alert] = t("job_orders.alerts.pay_magic_link_expired")
      redirect_to job_orders_path
    elsif @job_order.current_status == JobStatus.completed # no status (nil): not payable, as below
      link = @job_order.checkout_link # a refusal is already reported; the page says the link is unavailable
      if link.reason == :order_missing
        flash[:alert] = t("job_orders.alerts.pay_magic_link_expired")
        return redirect_to job_orders_path
      elsif link.reason == :invalid_status_row # the send-back to staff could not be written
        flash[:alert] = t("job_orders.alerts.pay_send_back_failed")
        return redirect_to job_order_path(@job_order.id)
      end
      @payment_link = link.value
      # The status may have changed under checkout_link (maybe on another connection): read it again, fresh.
      if @job_order.current_status == JobStatus.completed
        render "job_orders/pay"
      else
        # checkout_link found the invoice out of date and sent the order back to staff (or an owner change did)
        flash[:alert] = t("job_orders.alerts.pay_quote_changed")
        redirect_to job_order_path(@job_order.id)
      end
    else
      flash[:alert] = t("job_orders.alerts.pay_magic_link_expired")
      redirect_to job_order_path(@job_order.id)
    end
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

  # Customer-facing params: no staff-only fields, no owner (the owner is set to
  # the current user in #create).
  def job_order_create_params
    job_order_params.except(:staff_comments, :staff_files)
  end

  # Staff params (comments action). The owner can never be reassigned.
  def job_order_params
    params.require(:job_order).permit(
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

  # Where the order list is for the current user (an admin's is the admin list).
  def orders_list_path
    @user.admin? ? admin_job_orders_path : job_orders_path
  end

  def grant_access
    return if current_user.staff? || current_user.admin?
      flash[:alert] = t("job_orders.alerts.cannot_access_area")
      redirect_to root_path
    
  end

  # The quote form's writes, run by JobOrder#transition! under the order's row lock (the order was reloaded by
  # lock!, so its tasks are read fresh). Validation failures raise, which rolls the transition back.
  def apply_quote_params!
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

        @job_order.job_quote_line_items.create!(description: desc, price: price.presence || 0.0)
      end
    end

    # one scalar read from job_order; its other keys are not this action's to permit, so none is logged unpermitted
    fields = params[:job_order]
    staff_comments = fields[:staff_comments] if fields.is_a?(ActionController::Parameters)
    @job_order.staff_comments = staff_comments if staff_comments.is_a?(String) && staff_comments.present?
    @job_order.save!
  end

  # The customer's comment on a quote or a decline, posted to the order chat. Only after the transition committed:
  # the chat message's after_save notification enqueues a mail that a rolled-back transition must not send.
  def post_user_comment
    return if params[:user_comments].blank?

    @job_order.chat_messages.create(message: params[:user_comments], sender: current_user)
  end

  # The flash for a refused quote / decline. A paid order says so (JOB-04), decided from the status the operation read
  # under its lock (result.status), not from a re-read after the commit; invalid input says what was wrong.
  def refusal_alert(result, requote: false)
    case result.reason
    when :wrong_state
      return t("job_orders.alerts.quote_refused_paid") if JobOrder.money_taken_status?(result.status)
    when :change_invalid
      return "#{t('job_orders.alerts.error_while_updating')} #{ERB::Util.html_escape(result.error.message)}"
    when :draft_not_voidable
      return t("job_orders.alerts.requote_draft_order_failed") if requote
    end
    t(result.message_key)
  end

  # One status transition through JobOrder#transition! (row lock, source state and approve link checked under it).
  def update_status(
    param,
    current_status,
    true_status,
    need_false_status,
    false_status = nil,
    redirect_link = job_order_path(@job_order.id),
    actor: @user,
    approval_token: nil
  )
    # which status was asked for, decided from the param alone
    asked = param == "true" || (param == "false" && need_false_status)
    result = if asked
               @job_order.transition!(from: current_status, to: param == "true" ? true_status : false_status,
                                      actor: actor, approval_token: approval_token)
             else
               JobOrder::TransitionResult.refused(:wrong_state)
             end

    if result.ok?
      flash[:notice] = t(
        "job_orders.alerts.updated_job_status_to_x",
        status: @job_order.latest_status.job_status.t_name
      )
    else
      flash[:alert] = t(result.message_key)
    end

    if redirect_link.nil?
      result.ok?
    else
      respond_to do |format|
        format.html { redirect_to redirect_link }
        format.js { render "admin_row" }
      end
    end
  end
end
