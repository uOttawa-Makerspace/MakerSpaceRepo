class Admin::ReportGeneratorController < AdminAreaController
  layout 'admin_area'

  def index
  end

# New users/month
  def new_users
  	respond_to do |format|
  		format.html
  		format.csv {send_data ReportGenerator.new_user_report, filename: "new_users-#{Date.today}.csv" }
    end
  end

# Visitors/month
  def total_visits
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.lab_session_report, filename: "total_visits-#{Date.today}.csv" }
    end
  end

# Unique visitors/ month
  def unique_visits
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.unique_visitors_report, filename: "unique_visits-#{Date.today}.csv"}
    end
  end

# Diversity of users based on faculty
  def faculty_frequency
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.faculty_frequency_report, filename: "faculty_frequency-#{Date.today}.csv"}
    end
  end

# Diversity of users based on gender
  def gender_frequency
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.gender_frequesncy_report, filename: "gender_frequency-#{Date.today}.csv"}
    end
  end

  def training
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.training_report, filename: "gender_frequency-#{Date.today}.csv"}
    end
  end
end
