class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'
  require 'date'

  def index
    @report_types = [
        ['Trainings', :trainings],
        ['Visitors', :visitors],
        ['New Users', :new_users]
    ]
  end

  def generate
    range_type = params[:range_type]
    semester = params[:semester]
    year = params[:year]
    type = params[:type]

    case range_type
    when "semester"
      unless year and year.to_i > 0
        render :text => "Invalid year", status: 400
        return
      end

      year = year.to_i

      case semester
      when "winter"
        start_date = DateTime.new(year, 1, 1).beginning_of_day
        end_date = DateTime.new(year, 4, 30).end_of_day
      when "summer"
        start_date = DateTime.new(year, 5, 1).beginning_of_day
        end_date = DateTime.new(year, 8, 31).end_of_day
      when "fall"
        start_date = DateTime.new(year, 9, 1).beginning_of_day
        end_date = DateTime.new(year, 12, 31).end_of_day
      else
        render :text => "Invalid semester", status: 400
        return
      end
    when "date_range"
      begin
        start_date = Date.parse(params[:from_date])
      rescue ParseError
        render :text => "Failed to parse start date"
        return
      end

      begin
        end_date = Date.parse(params[:to_date])
      rescue ParseError
        render :text => "Failed to parse end date"
        return
      end
    else
      render :text => "Invalid range type", status: 400
      return
    end

    case type
    when "visitors"
      spreadsheet = ReportGenerator.generate_visitors_report(start_date, end_date)
    when "trainings"
      spreadsheet = ReportGenerator.generate_trainings_report(start_date, end_date)
    when "new_users"
      spreadsheet = ReportGenerator.generate_new_users_report(start_date, end_date)
    else
      render :text => "Unknown report type", status: 400
      return
    end

    start_date_str = start_date.strftime("%Y-%m-%d")
    end_date_str = end_date.strftime("%Y-%m-%d")

    send_data spreadsheet.to_stream.read, :type => "application/xlsx", :filename => type + "_" + start_date_str + "_" + end_date_str + ".xlsx"
  end
end
