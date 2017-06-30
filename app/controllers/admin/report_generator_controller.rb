class Admin::ReportGeneratorController < AdminAreaController

  layout 'admin_area'

  def index
  end

  def repor1_generator
    @users = User.in_last_month
    attributes = %w{id name username email faculty program created_at}
    @users.to_csv(*attributes)
  end

  def report1
  	respond_to do |format|
  		format.html
  		format.csv {send_data repor1_generator() }

      ##Should move this
      MsrMailer.send_report("admin@email.com", repor1_generator()).deliver
    end
  end

  def report2
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
    respond_to do |format|
      format.html
      format.csv {send_data @labs.to_csv(column)}
    end
  end

  def report3
    respond_to do |format|
      format.html
      format.csv {send_data faculty_frequency_counter()}

    end
  end

  def faculty_frequency_counter
      @faculty_freq = User.group(:faculty).count(:faculty)
      CSV.generate do |csv|
        csv << @faculty_freq.keys
        csv << @faculty_freq.values
      end
  end
end
