class ReportGenerator


  def self.new_user_report
    @users = User.in_last_month
    attributes = %w{id name username email faculty program created_at}
    @users.to_csv(*attributes)
  end

  def self.lab_session_report
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

  def self.faculty_frequency_report
      @faculty_freq = User.group(:faculty).count(:faculty)
      CSV.generate do |csv|
        csv << @faculty_freq.keys
        csv << @faculty_freq.values
      end
  end
end
