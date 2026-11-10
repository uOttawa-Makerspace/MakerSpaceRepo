class PrinterIssuesController < StaffAreaController
  layout "staff_area"

  def index
    @issues = PrinterIssue.all.order(:printer_id)
    @issues_summary =
      @issues
        .filter(&:active)
        .group_by do |issue|
          PrinterIssue.summaries.values.detect do |s|
            issue.summary.include? s
          end || "Other"
        end

    @maintenance_email = Setting.maintenance_email

    respond_to do |format|
      format.html
      format.json do
        render json: {
          issues: @issues.map do |issue|
            {
              id: issue.id,
              printer_id: issue.printer_id,
              reporter: issue.reporter&.name,
              summary: issue.summary,
              description: issue.description,
              created_at: issue.created_at,
              active: issue.active
            }
          end
        }
      end
    end
  end

  def show
    @issue = PrinterIssue.find(params[:id])
  end

  def new
    @issue ||= PrinterIssue.new
    @printers = Printer.show_options.all
    @issueSummary =
      @printers
        .filter_map do |printer|
          count = printer.count_printer_issues.count
          [printer.id, printer.count_printer_issues] if count.positive?
        end
        .to_h
  end

  def create
    printer = Printer.find_by(id: printer_issue_params[:printer_id])
    @issue =
      PrinterIssue.new(
        printer: printer,
        summary: printer_issue_params[:summary],
        description: printer_issue_params[:description],
        reporter: current_user,
        active: true
      )

    if @issue.save
      redirect_to @issue, alert: (I18n.t("errors.printers.notification_not_sent") unless send_notification_email(@issue))
    else
      new
      flash.now[:alert] = validation_message(@issue, "errors.printers.issue_not_created")
      render :new, status: :unprocessable_content
    end
  end

  def edit
    new
    @issue = PrinterIssue.find(params[:id])
    render :new, locals: { is_edit: true }
  end

  def update
    # Ideally, all updates happen from /printer_issues
    issue = PrinterIssue.find(params[:id])
    unless issue.update(printer_issue_params.except(:printer_id))
      flash[:alert] = validation_message(issue, "errors.printers.issue_not_updated")
      return redirect_to printer_issues_path
    end
    if issue.active
      redirect_to issue
    else
      redirect_to printer_issues_path
    end
  end

  # POST /printer_issues/:id/resolve (MakerRepo React app): same as the staff
  # UI's resolve, i.e. update(active: false).
  def resolve
    issue = PrinterIssue.find(params[:id])
    if issue.update(active: false)
      head :ok
    else
      render json: { errors: issue.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    unless current_user.admin?
      redirect_to printer_issues_path, alert: I18n.t("errors.printers.issue_delete_admin_only")
      return
    end
    issue = PrinterIssue.find(params[:id])
    flash[:alert] = validation_message(issue, "errors.printers.issue_not_deleted") unless issue.destroy
    redirect_to printer_issues_path, status: :see_other
  end

  def update_notification_email
    email = params[:notification_email].to_s.strip

    if email.blank?
      Setting.maintenance_email = nil
      flash[:notice] = "Notification email removed."
    elsif email.match?(/\A[^@\s]+@[^@\s]+\z/)
      Setting.maintenance_email = email
      flash[:notice] = "Notification email updated to #{email}."
    else
      flash[:alert] = "Invalid email address."
    end

    redirect_to printer_issues_path
  end

  private

  def printer_issue_params
    params.require(:printer_issue).permit(
      :printer_id,
      :summary,
      :description,
      :active
    )
  end

  # Queues the maintenance notification; false when the queue refused it (reported). The issue is
  # already saved, so that is a notice to the reporter and not an error page.
  def send_notification_email(issue)
    recipient = Setting.maintenance_email
    return true if recipient.blank?

    MsrMailer.new_printer_issue(issue, recipient).deliver_later
    true
  rescue ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError => e
    report_unexpected(e, source: "printer_issues#create")
    false
  end
end