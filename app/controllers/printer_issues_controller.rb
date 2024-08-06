class PrinterIssuesController < StaffAreaController
  layout "staff_area"

  def index
    @issues = PrinterIssue.all
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
  end

  def destroy
  end

  def history
  end

  private

  def printer_issue_params
    params.require(:printer_issue).permit(:printer, :summary, :description)
  end
end
