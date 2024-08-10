class PrinterIssuesController < StaffAreaController
  layout "staff_area"

  def index
    @issues = PrinterIssue.all.order(:printer_id)
    @issues_summary =
      @issues.group_by do |issue|
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
    @issue = PrinterIssue.new
    @printers = Printer.show_options.all
  end

  def create
    printer = Printer.find_by_id(printer_issue_params[:printer])
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
      flash[:alert] = "Failed to create issue"
      redirect_to printer_issues_path
    end
  end

  def edit
  end

  def update
    issue = PrinterIssue.find_by(id: params[:id])
    unless issue.update(printer_issue_params)
      flash[:alert] = "Failed to update printer issue #{params[:id]}"
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
