class PrinterIssuesController < StaffAreaController
  layout "staff_area"

  def index
    @issues = PrinterIssue.all.order(:printer_id)
    @issues_summary =
      @issues
        .filter(&:active)
        .group_by do |issue|
          if (PrinterIssue.summaries.values.include? issue.summary)
            issue.summary
          else
            "Other"
          end
        end
  end

  def show
    @issue = PrinterIssue.find_by(id: params[:id])
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
    printer = Printer.find_by(id: printer_issue_params[:printer])
    @issue =
      PrinterIssue.new(
        printer: printer,
        summary: printer_issue_params[:summary],
        description: printer_issue_params[:description],
        reporter: current_user,
        active: true
      )

    if @issue.save
      redirect_to @issue
    else
      new # set previous variables
      flash[
        :alert
      ] = "Failed to create issue: #{@issue.errors.full_messages.join("<br />")}".html_safe
      # All this to keep form data on error
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    issue = PrinterIssue.find_by(id: params[:id])
    unless issue.update(printer_issue_params)
      flash[
        :alert
      ] = "Failed to update printer issue #{params[:id]}, #{issue.errors.first.message}"
    end
    redirect_back fallback_location: printer_issues_path
  end

  def destroy
  end

  def history
  end

  private

  def printer_issue_params
    params.require(:printer_issue).permit(
      :printer,
      :summary,
      :description,
      :active
    )
  end
end
