class ReportGenerator


  def self.new_user_report
    @users = User.in_last_month
    attributes = %w{id name username email gender faculty program created_at}
    @users.to_csv(*attributes)
  end

  def self.lab_session_report
    @labs = LabSession.in_last_month
    column = []
    column << ["lab_id", "sign_in_time", "user_id", "name", "email", "gender", "faculty", "program"]
    @labs.each do |lab|
      row = []
      row << lab.id << lab.sign_in_time
      row << lab.user.id << lab.user.name << lab.user.email << lab.user.gender << lab.user.faculty << lab.user.program
      column << row
    end
    column << [] << ["Total visitors this month:", @labs.length] << ["# of Unique Visits:", @labs.distinct.count(:user_id)]
    @labs.to_csv(column)
  end

  def self.unique_visitors_report
    @labs = LabSession.in_last_month
    @unique_visits = @labs.select('DISTINCT user_id')
    column = []
    column << ["id" , "name", "username", "email", "gender", "faculty", "program" ]
    @unique_visits.each do |lab|
      @visitor = lab.user
      row = []
      row << @visitor.id << @visitor.name << @visitor.username << @visitor.email << @visitor.gender << @visitor.faculty << @visitor.program
      column << row
    end
    column << [] << ["# of Unique Visits:", @labs.distinct.count(:user_id)]
    @unique_visits.to_csv(column)
  end

  def self.faculty_frequency_report
      @faculty_freq = User.group(:faculty).count(:faculty)
      CSV.generate do |csv|
        csv << @faculty_freq.keys
        csv << @faculty_freq.values
      end
  end

  def self.gender_frequesncy_report
    @gender_freq = User.group(:gender).count(:gender)
    CSV.generate do |csv|
      csv << @gender_freq.keys
      csv << @gender_freq.values
    end
  end

end
