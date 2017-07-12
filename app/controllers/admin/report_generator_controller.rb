class Admin::ReportGeneratorController < AdminAreaController
  # before_action :report1_generator
  layout 'admin_area'

  def index
  end

# New users/month
  def report1
  	respond_to do |format|
  		format.html
  		format.csv {send_data ReportGenerator.new_user_report }
    end
  end

# Visitors/month
  def report2
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.lab_session_report }
    end
  end

# Diversity of users based on faculty
  def report3
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.faculty_frequency_report}
    end
  end

  def report4
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.gender_frequesncy_report}
    end
  end
end
