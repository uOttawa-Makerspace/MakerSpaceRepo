class JobOrdersController < ApplicationController
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
                  steps
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
  before_action :wizard, only: %w[steps]
  before_action :allow_edit, only: %w[steps]

  def index
    @job_orders = []
    @archived_job_orders = []
    @drafts = []
    @user.job_orders.not_deleted.each do |jo|
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

    if current_user.id == @job_order.user_id
      @unread_messages = @job_order.chat_messages.unread(current_user)
      @unread_messages.update_all(is_read: true) # rubocop:disable Rails/SkipsModelValidations
    end

    return unless @job_order.nil?
      flash[:alert] = t("job_orders.alerts.job_order_not_found")
      redirect_to job_orders_path     
    
  end

  def new
    @job_order = JobOrder.new
  end

  def steps
    error = []

    if @job_order.present? && @job_order.user == @user
      if params[:keep_files].present?
        (
          @job_order.user_files.pluck(:id) - params[:keep_files].map(&:to_i)
        ).each { |file_id| @job_order.user_files.find(file_id).purge }
      elsif params[:should_delete_user_files] && params[:keep_files].blank?
        @job_order.user_files.pluck(:id).each do |file_id|
          @job_order.user_files.find(file_id).purge
        end
      end

      if params[:job_order].present?
        if params[:job_service_name].present?
          @job_order.job_services << JobService.create!(
            name: params[:job_service_name],
            job_service_group_id: params[:job_order][:job_service_group_id],
            user_created: true,
            job_order_id: @job_order.id
          )
        end

        if params[:job_order][:job_service_ids] == "custom"
          params[:job_order][:job_service_ids] = @job_order.job_services.last.id
        end

        error << t("job_orders.alerts.please_upload_valid_file_type") unless update_job_order_with_comments(@job_order, 
job_order_params.to_h)
      end

      if params[:change_options].present? && params[:change_options] == "true" && !@job_order.add_options(params)
        error = t("job_orders.alerts.options_have_not_been_saved")
      end
    else
      error << t("job_orders.alerts.job_order_not_found")
    end

    if error.present?
      redirect_to job_order_steps_path(
                    @job_order,
                    step: (params[:step].to_i - 1)
                  )
      flash[:alert] = t("job_orders.alerts.error_while_saving_step") +
        error.join(", ")
    else
      @step = @job_order.max_step if @job_order.max_step < @step
      case @step
      when 1
        render "job_orders/wizard/order_type"
      when 2
        @job_type = JobType.find(@job_order.job_type_id)
        @service_groups =
          JobServiceGroup.all.where(job_type: @job_order.job_type).order(:id)
        render "job_orders/wizard/service"
      when 3
        @options =
          JobOption
            .all
            .joins(:job_types)
            .where(job_types: { id: @job_order.job_type_id })
        render "job_orders/wizard/options"
      when 4
        render "job_orders/wizard/submission"
      when 5
        if @job_order.job_order_statuses.last.job_status !=
             JobStatus::STAFF_APPROVAL
          @job_order.job_order_statuses << JobOrderStatus.create!(
            job_order: @job_order,
            job_status: JobStatus::STAFF_APPROVAL,
            user: @user
          )
          JobOrderMailer.send_job_submitted(@job_order.id).deliver_now
          flash[:notice] = t(
            "job_orders.alerts.job_order_submitted_for_approval"
          )
        else
          flash[:notice] = t("job_orders.alerts.job_order_updated")
        end
        redirect_to job_order_path(@job_order.id)
      else
        redirect_to job_orders_path
      end
    end
  end

  def create
    @job_order = JobOrder.new(job_order_params)
    @job_order.user = @user

    # Force job_type_id = 3 if it's the "Need Design Help" flow
    @job_order.job_type_id = if params[:redirect_step].to_i == 2
      JobType.where(name: "Design Services") .first.id
    else 
      JobType.all.first.id
    end

    if @job_order.save
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: JobStatus::DRAFT,
        user: @user
      )

      if @job_order.save
        redirect_to job_order_steps_path(job_order_id: @job_order.id, step: params[:redirect_step] || 1)
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

  def completed_email_modal
    @message =
      JobOrderMessage.find_by(name: "processed").retrieve_message(@job_order.id)
    render layout: false
  end

  def comments_modal
    render layout: false
  end

  def quote
    error = false
    if params[:approved].present? && params[:approved] == "true"
      if update_job_order_with_comments(@job_order, job_order_params.to_h)
        quote = JobOrderQuote.create(service_fee: params[:service_fee])
        if @job_order.save
          params.permit!
          params.to_h.each do |key, value|
            if key.include?("quote_service_amount_")
              id = +key.delete_prefix("quote_service_amount_").to_i
              if params["quote_service_per_unit_#{id}"].present?
                JobOrderQuoteService.create!(
                  job_service_id: id,
                  job_order_quote: quote,
                  quantity: value,
                  per_unit: params["quote_service_per_unit_#{id}"]
                )
              end
            end

            if key.include?("quote_option_amount_")
              id = +key.delete_prefix("quote_option_amount_").to_i
              JobOrderQuoteOption.create!(
                job_option_id: id,
                job_order_quote: quote,
                amount: value
              )
            end

            if key.include?("quote_extra_amount_")
              id = +key.delete_prefix("quote_extra_amount_").to_i
              JobOrderQuoteTypeExtra.create!(
                job_order_quote: quote,
                price: value
              )
            end

            error = true unless @job_order.update(job_order_quote: quote)
          end

          unless error
            @job_order.job_order_statuses << JobOrderStatus.create(
              job_order: @job_order,
              job_status: JobStatus::USER_APPROVAL,
              user: @user
            )
          end
          if @job_order.save
            JobOrderMailer.send_job_quote(@job_order.id).deliver_now
          else
            error = true
          end
        else
          error = true
        end
      else
        error = true
      end
    elsif params[:approved].present? && params[:approved] == "false"
      if update_job_order_with_comments(@job_order, job_order_params.to_h)
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
    # only for staff comments so dont need update_job_order_with_comments
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
  end

  def assign_staff
    @job_order = JobOrder.find_by(id: params[:job_order_id], is_deleted: false)
    if @job_order.present? && (@user.admin? || @user.id == params[:staff_id].to_i)
      @job_order.assigned_staff_id = params[:staff_id]
      if @job_order.save
        flash[:notice] = "#{@job_order.assigned_staff&.name || "No staff"} has been assigned to this job order."

        if @job_order.assigned_staff.present? && @user.admin? && @job_order.assigned_staff != @user
          JobOrderMailer.staff_assigned(@job_order.id, @job_order.assigned_staff.id).deliver_later(queue: :solid_queue)
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
    @service_groups = JobServiceGroup.all.order(:job_type_id)
    @services = JobService.all.not_user_created.order(:job_service_group_id)
    @options = JobOption.all
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
  end

  private

  def update_job_order_with_comments(job_order, params)
    comments = params.delete(:comments)
    comment_from_staff = params.delete(:user_comments)

    success = job_order.update(params)

    if success && comments.present?
      job_order.chat_messages.create(
        message: comments,
        sender: current_user
      )
    end

    if success && comment_from_staff.present?
      job_order.chat_messages.create(
        message: comment_from_staff,
        sender: current_user,
      )
    end

    success
  end

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

  def allow_edit
    return if @job_order.allow_edit? || @user.admin?
      flash[:alert] = t("job_orders.alerts.cannot_edit")
      redirect_to job_orders_path
    
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

  def wizard
    @step = params[:step].present? ? params[:step].to_i : 1
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
