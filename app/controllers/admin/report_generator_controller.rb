class Admin::ReportGeneratorController < AdminAreaController
  # before_action :report1_generator
  layout 'admin_area'

  def index
  end

# New users/month
  def report1_generator
    @users = User.in_last_month
    attributes = %w{id name username email faculty program created_at}
    @users.to_csv(*attributes)
  end

  def report1
  	respond_to do |format|
  		format.html
  		format.csv {send_data report1_generator() }
    end
  end

# Visitors/month
  def report2_generator
    @labs = LabSession.in_last_month
    column = []
    column << ["lab_id", "sign_in_time", "user_id", "name", "email", "faculty", "program"]
    @labs.each do |lab|
      row = []
      row << lab.id << lab.sign_in_time
      user = lab.user
      row << lab.user.id << lab.user.name << lab.user.email << user.faculty << lab.user.program
      column << row
    end
    column << [] << ["Total visitors this month:", @labs.length]
    @labs.to_csv(column)
  end

  def report2
    respond_to do |format|
      format.html
      format.csv {send_data report2_generator() }
    end
  end

  def report3_generator
      @faculty_freq = User.group(:faculty).count(:faculty)
      CSV.generate do |csv|
        csv << @faculty_freq.keys
        csv << @faculty_freq.values
      end
  end

  def report3
    respond_to do |format|
      format.html
      format.csv {send_data report3_generator()}
    end
  end

end
