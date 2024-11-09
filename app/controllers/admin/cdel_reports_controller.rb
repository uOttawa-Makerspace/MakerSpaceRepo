# frozen_string_literal: true

class Admin::CdelReportsController < AdminAreaController
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
      send_data CdelReportGenerator.generate_certifications_report(
                  start_date,
                  end_date
                )
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

  def start_date
    case params[:date_format]
    when "range"
      params[:start_date].to_date
    when "semester"
      case params[:semester_term]
      when "Fall"
        Date.new(params[:semester_year].to_i, 9, 1)
      when "Winter"
        Date.new(params[:semester_year].to_i, 1, 1)
      when "Summer"
        Date.new(params[:semester_year].to_i, 5, 1)
      end
    end
  end

  def end_date
    case params[:date_format]
    when "range"
      params[:end_date].to_date
    when "semester"
      case params[:semester_term]
      when "Fall"
        Date.new(params[:semester_year].to_i, 12, 31)
      when "Winter"
        Date.new(params[:semester_year].to_i, 4, 30)
      when "Summer"
        Date.new(params[:semester_year].to_i, 8, 31)
      end
    end
  end
end
