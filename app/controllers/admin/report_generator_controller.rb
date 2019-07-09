class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'
  require 'date'
  def index
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
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
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

  	respond_to do |format|
  		format.html
  		format.csv {send_data ReportGenerator.new_user_report(@start_date , @end_date), filename: "new_makerepo_users-#{Date.today}.csv" }
    end
  end

# Visitors
  def total_visits
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.lab_session_report(@start_date , @end_date), filename: "total_visits-#{Date.today}.csv" }
    end
  end

# Unique visitor
  def unique_visits
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.unique_visitors_report(@start_date , @end_date), filename: "unique_visits-#{Date.today}.csv"}
    end
  end

# Diversity of users based on faculty
  def faculty_frequency
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.faculty_frequency_report(@start_date , @end_date), filename: "faculty_frequency-#{Date.today}.csv"}
    end
  end

# Diversity of users based on gender
  def gender_frequency
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.gender_frequency_report(@start_date , @end_date), filename: "gender_frequency-#{Date.today}.csv"}
    end
  end

  def training
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.training_report(@start_date , @end_date), filename: "trainings-#{Date.today}.csv"}
    end
  end

  def makerspace_training
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.makerspace_training_report(@start_date, @end_date), filename: "mspace_trainings-#{Date.today}.csv"}
    end
  end


  def mtc_training
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.mtc_training_report(@start_date, @end_date), filename: "mtc_trainings-#{Date.today}.csv"}
    end
  end


  # repositories
  def repository
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end

    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.project_report(@start_date , @end_date) , filename: "repositories-#{Date.today}.csv"}
    end
  end


  def peak_hrs
    unless session[:selected_dates]
      @start_date = 1.month.ago.beginning_of_day
      @end_date = DateTime.current.end_of_day
    else
      @start_date = DateTime.parse(selected_dates[0]).beginning_of_day
      @end_date = DateTime.parse(selected_dates[1]).end_of_day
    end
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.frequency_hours_report(@start_date, @end_date), filename: "visits-raw-data-#{Date.today}.csv"}
    end
  end

  def total_visits_per_term
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.total_visits_per_term_report , filename: "total_visits_per_term-#{Date.today}.csv"}
    end
  end

  def unique_visits_detail
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.unique_visits_detail_report , filename: "detail_unique_visits_per_term-#{Date.today}.csv"}
    end
  end

  def total_visits_detail
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.total_visits_detail_report , filename: "detail_total_visits_per_term-#{Date.today}.csv"}
    end
  end

  def unique_visits_ceed
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.unique_visits_ceed , filename: "CEED_unique_visits_per_term-#{Date.today}.csv"}
    end
  end

  def seasonal_certification_report
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.seasonal_certification_report , filename: "Certifications_per_term-#{Date.today}.csv"}
    end
  end

  def seasonal_training_report
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.seasonal_training_report , filename: "Trainings_per_term-#{Date.today}.csv"}
    end
  end
end
