# frozen_string_literal: true

class Admin::CdelReportsController < AdminAreaController
  rescue_from ReportPeriod::Invalid do |error|
    render plain: error.message, status: :bad_request
  end

  def index
  end

  def generate
    # We test for the *presence* of a value to determine
    # which button was clicked. Is this a bad idea? We'll never know...
    report = nil

    # Get data
    if params[:visitors]
      report =
        CdelReportGenerator.generate_visitors_report(start_date, end_date)
    elsif params[:certifications]
      report =
        CdelReportGenerator.generate_certifications_report(start_date, end_date)
    elsif params[:new_users]
      report =
        CdelReportGenerator.generate_new_users_report(start_date, end_date)
    end

    # error checking
    if report.present?
      send_data report[:data], filename: report[:filename]
    else
      head :bad_request
    end
  end

  private

  def period
    @period ||=
      case params[:date_format]
      when "range"
        ReportPeriod.parse(params[:start_date], params[:end_date])
      when "semester"
        ReportPeriod.semester(params[:semester_term], params[:semester_year])
      else
        raise ReportPeriod::Invalid, "Choose a semester or a date range"
      end
  end

  def start_date
    period.first_day
  end

  def end_date
    period.last_day
  end
end
