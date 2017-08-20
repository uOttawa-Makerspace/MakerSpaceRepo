class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'
  require 'date'

  def index
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end
  end

  def select_date_range
    session[:selected_dates] = nil
    @start = Date::civil(params[:start][:year].to_i, params[:start][:month].to_i,
                      params[:start][:day].to_i)
    @start_date = Time.zone.at(@start.to_time).to_datetime

    @end = Date::civil(params[:end][:year].to_i, params[:end][:month].to_i,
                      params[:end][:day].to_i)
    @end_date = Time.zone.at(@end.to_time).to_datetime

    selected_dates << @start_date << @end_date
    redirect_to :back
  end

# New users
  def new_users
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

  	respond_to do |format|
  		format.html
  		format.csv {send_data ReportGenerator.new_user_report(@start_date , @end_date), filename: "new_users-#{Date.today}.csv" }
    end
  end

# Visitors
  def total_visits
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.lab_session_report(@start_date , @end_date), filename: "total_visits-#{Date.today}.csv" }
    end
  end

# Unique visitor
  def unique_visits
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.unique_visitors_report(@start_date , @end_date), filename: "unique_visits-#{Date.today}.csv"}
    end
  end

# Diversity of users based on faculty
  def faculty_frequency
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.faculty_frequency_report(@start_date , @end_date), filename: "faculty_frequency-#{Date.today}.csv"}
    end
  end

# Diversity of users based on gender
  def gender_frequency
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.gender_frequesncy_report(@start_date , @end_date), filename: "gender_frequency-#{Date.today}.csv"}
    end
  end

  def training
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.training_report(@start_date , @end_date), filename: "trainings-#{Date.today}.csv"}
    end
  end

  # repositories
  def repository
    if session[:selected_dates] == nil
      @start_date = 1.month.ago
      @end_date = DateTime.current
    else
      @start_date = DateTime.parse(selected_dates[0])
      @end_date = DateTime.parse(selected_dates[1])
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.project_report(@start_date , @end_date) , filename: "repositories-#{Date.today}.csv"}
    end
  end
end
