# frozen_string_literal: true

class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'
  require 'date'

  def index
    @report_types = [
      ['Certifications', :certifications],
      ['New Projects', :new_projects],
      ['New Users', :new_users],
      ['Trainings', :trainings],
      ['Training Attendees', :training_attendees],
      ['Visitors', :visitors],
      ['Visits by Hour', :visits_by_hour]
    ]
  end

  def popular_hours
    @space = @user.lab_sessions&.last&.space || Space.first
    @spaces = Space.all.order(name: :asc)
    @weekdays = Date::DAYNAMES
  end

  def popular_hours_per_period
    if params[:start_date].blank? || params[:end_date].blank?
      redirect_to admin_report_generator_popular_hours_path, alert: 'You need to select dates to get Popular Hours for a specific period.'
    else
      @space = @user.lab_sessions&.last&.space || Space.first
      @weekdays = Date::DAYNAMES
      @info = LabSession.get_popular_hours_per_period(params[:start_date].to_date, params[:end_date].to_date, @space.id)
    end
  end


  def generate
    range_type = params[:range_type]
    term = params[:term]
    year = params[:year]
    type = params[:type]

    case range_type
    when 'semester'
      unless year && (year.to_i > 0)
        render plain: 'Invalid year', status: :bad_request
        return
      end

      year = year.to_i

      case term
      when 'winter'
        start_date = DateTime.new(year, 1, 1).beginning_of_day
        end_date = DateTime.new(year, 4, 30).end_of_day
      when 'summer'
        start_date = DateTime.new(year, 5, 1).beginning_of_day
        end_date = DateTime.new(year, 8, 31).end_of_day
      when 'fall'
        start_date = DateTime.new(year, 9, 1).beginning_of_day
        end_date = DateTime.new(year, 12, 31).end_of_day
      else
        render plain: 'Invalid term', status: :bad_request
        return
      end
    when 'date_range'
      begin
        start_date = Date.parse(params[:from_date]).to_datetime.beginning_of_day
      rescue ParseError
        render plain: 'Failed to parse start date'
        return
      end

      begin
        end_date = Date.parse(params[:to_date]).to_datetime.end_of_day
      rescue ParseError
        render plain: 'Failed to parse end date'
        return
      end
    else
      render plain: 'Invalid range type', status: :bad_request
      return
    end

    case type
    when 'visitors'
      spreadsheet = ReportGenerator.generate_visitors_report(start_date, end_date)
    when 'trainings'
      spreadsheet = ReportGenerator.generate_trainings_report(start_date, end_date)
    when 'certifications'
      spreadsheet = ReportGenerator.generate_certifications_report(start_date, end_date)
    when 'new_users'
      spreadsheet = ReportGenerator.generate_new_users_report(start_date, end_date)
    when 'training_attendees'
      spreadsheet = ReportGenerator.generate_training_attendees_report(start_date, end_date)
    when 'new_projects'
      spreadsheet = ReportGenerator.generate_new_projects_report(start_date, end_date)
    when 'visits_by_hour'
      spreadsheet = ReportGenerator.generate_peak_hours_report(start_date, end_date)
    else
      render plain: 'Unknown report type', status: :bad_request
      return
    end

    start_date_str = start_date.strftime('%Y-%m-%d')
    end_date_str = end_date.strftime('%Y-%m-%d')

    send_data spreadsheet.to_stream.read, type: 'application/xlsx', filename: type + '_' + start_date_str + '_' + end_date_str + '.xlsx'
  end
end
