class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in,
                except: %i[
                  user_magic_approval
                  user_magic_approval_confirmation
                  pay
                  stripe_success
                  stripe_cancelled
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
                  quote
                  resend_quote_email
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
                  quote
                  invoice
                  resend_quote_email
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
      elsif jo.job_order_statuses.last.job_status == JobStatus::DECLINED ||
            jo.job_order_statuses.last.job_status == JobStatus::PICKED_UP
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
    error = []

    if @job_order.present? && @job_order.user == @user
      if params[:keep_files].present?
        (
          @job_order.user_files.pluck(:id) - params[:keep_files].map(&:to_i)
        ).each { |file_id| @job_order.user_files.find(file_id).purge }
      elsif params[:should_delete_user_files] && !params[:keep_files].present?
        (@job_order.user_files.pluck(:id)).each do |file_id|
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
        unless @job_order.update(job_order_params)
          error << "Please make sure you have a uploaded a valid filetype."
        end
      end

      if params[:change_options].present? && params[:change_options] == "true"
        unless @job_order.add_options(params)
          error = "The options have not successfully been saved."
        end
      end
    else
      error << "The Job Order hasn't been found."
    end

    if error.length > 0
      redirect_to job_order_steps_path(
                    @job_order,
                    step: (params[:step].to_i - 1)
                  )
      flash[:alert] = "An error occurred while saving the job order step. " +
        error.join(", ")
    else
      @step = @job_order.max_step if (@job_order.max_step < @step)
      case @step
      when 1
        render "job_orders/wizard/order_type"
      when 2
        @job_type = JobType.find(@job_order.job_type_id)
        @job_type_extras =
          JobTypeExtra.where(job_type_id: @job_order.job_type_id)
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
          flash[
            :notice
          ] = "Your job order has been submitted for staff approval!"
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
      @job_order.job_order_statuses << JobOrderStatus.create(
        job_order: @job_order,
        job_status: JobStatus::DRAFT,
        user: @user
      )
      if @job_order.save
        redirect_to job_order_steps_path(job_order_id: @job_order.id, step: 2)
      else
        @job_order.update(is_deleted: true)
        redirect_to new_job_orders_path
      end
    else
      flash[
        :alert
      ] = "An error occurred while trying to create the Job Order. Please try again."
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
      flash[
        :alert
      ] = "The following Job Order Approval link is invalid or has expired. Please Sign In to look at the Job Order Page."
      redirect_to job_orders_path
    end
  end

  def user_magic_approval_confirmation
    @token = params[:token]
    verifier = Rails.application.message_verifier(:job_order_id)
    if verifier.valid_message?(params[:token])
      @job_order =
        JobOrder.where(id: verifier.verify(@token), is_deleted: false).first
      if update_status(
           params[:approved],
           [JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER],
           JobStatus::WAITING_PROCESSED,
           true,
           JobStatus::DECLINED,
           nil
         )
        @status = true
      else
        @status = false
      end
      render "job_orders/magic_approval_confirmation"
    else
      flash[
        :alert
      ] = "An error occurred while trying to accept or deny the Job Order. Please try again."
      redirect_to job_orders_path
    end
  end

  def user_approval
    redirect_link =
      @job_order.user == @user ? job_orders_path : admin_job_orders_path
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
      format.html { redirect_to redirect_link }
      format.js { render "admin_row" }
    end
  end

  def quote_modal
    @job_type_extras = JobTypeExtra.where(job_type: @job_order.job_type)
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
      "Your Job Order ##{@job_order.id} has now been completed. You can now pay for your order online by following <a href='https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order'>these instructions</a>. You can check the <a href='https://makerepo.com/job_orders'>Job Order page</a> for details."
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
                job_type_extra_id: id,
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
      if @job_order.update(job_order_params)
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
      flash[
        :notice
      ] = "You have updated the Job Order Status to: #{@job_order.job_order_statuses.last.job_status.name}!"
    else
      flash[
        :alert
      ] = "An error occurred while updating the Job Order Status. Please try again later."
    end
    respond_to do |format|
      format.html { redirect_to admin_job_orders_path }
      format.js { render "admin_row" }
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
      format.html { redirect_to admin_job_orders_path }
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
    if @job_order.save
      JobOrderMailer.send_job_quote(@job_order.id, true).deliver_now
    end
    respond_to do |format|
      format.html { redirect_to admin_job_orders_path }
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

  def admin
    @statuses = [
      { name: "Waiting for Staff Approval", status: JobStatus::STAFF_APPROVAL },
      { name: "Waiting for User Approval", status: JobStatus::USER_APPROVAL },
      { name: "Sent a Quote Reminder", status: JobStatus::SENT_REMINDER },
      { name: "Waiting to be processed", status: JobStatus::WAITING_PROCESSED },
      { name: "Currently being processed", status: JobStatus::BEING_PROCESSED },
      { name: "Waiting for Payment", status: JobStatus::COMPLETED },
      { name: "Waiting for Pick-Up", status: JobStatus::PAID },
      { name: "Archived", status: [JobStatus::PICKED_UP, JobStatus::DECLINED] }
    ]

    if params[:query_date].present?
      session[:query_date] = params[:query_date].to_i
    end

    if !session[:query_date].present? || session[:query_date] == 0
      session[:query_date] = 0
      @job_orders = JobOrder.all.not_deleted.without_drafts.order_by_expedited
    else
      @job_orders =
        JobOrder
          .all
          .not_deleted
          .without_drafts
          .where(created_at: session[:query_date].days.ago..)
          .order_by_expedited
    end
  end

  def settings
    @service_groups = JobServiceGroup.all.order(:job_type_id)
    @services = JobService.all.not_user_created.order(:job_service_group_id)
    @options = JobOption.all
    @job_types = JobType.all
    @job_type_extras = JobTypeExtra.all
  end

  def invoice
    render pdf: "invoice", template: "job_orders/invoice.html.erb"
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
      @stripe_session =
        Stripe::Checkout::Session.create(
          success_url: stripe_success_job_orders_url,
          cancel_url: stripe_cancelled_job_orders_url,
          mode: "payment",
          line_items: @job_order.generate_line_items,
          billing_address_collection: "required",
          client_reference_id: "job-order-#{@job_order.id}"
        )
      render "job_orders/pay"
    else
      flash[
        :alert
      ] = "The following Job Order Payment link is invalid or has expired. Please Sign In to look at the Job Order Page."
      redirect_to job_orders_path
    end
  end

  def stripe_success
  end

  def stripe_cancelled
  end

  private

  def set_job_order
    if JobOrder.where(id: params[:job_order_id], is_deleted: false).present? ||
         JobOrder.where(id: params[:id], is_deleted: false).present?
      jo =
        JobOrder.where(
          id:
            (
              if params[:job_order_id].present?
                params[:job_order_id]
              else
                params[:id]
              end
            ),
          is_deleted: false
        ).first
      if @user.admin? | @user.staff? || @user.id == jo.user_id
        @job_order = jo
      else
        flash[:alert] = "You do not have permission to view this job order."
        redirect_to new_job_orders_path
      end
    else
      flash[:alert] = "You do not have permission to view this job order."
      redirect_to new_job_orders_path
    end
  end

  def allow_edit
    unless @job_order.allow_edit? || @user.admin?
      flash[
        :alert
      ] = "You cannot edit this Job Order. Please contact makerspace@uottawa.ca for assistance."
      redirect_to job_orders_path
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
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
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
    redirect_link = admin_job_orders_path
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
      flash[
        :notice
      ] = "You have updated the Job Order Status to: #{@job_order.job_order_statuses.last.job_status.name}!"
    else
      flash[
        :alert
      ] = "An error occurred while updating the Job Order Status. Please try again later."
    end

    if redirect_link == nil
      !error
    else
      respond_to do |format|
        format.html { redirect_to redirect_link }
        format.js { render "admin_row" }
      end
    end
  end
end
