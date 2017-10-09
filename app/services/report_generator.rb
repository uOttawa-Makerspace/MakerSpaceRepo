class ReportGenerator

  def self.new_user_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @users = User.between_dates_picked(start_date, end_date)
    attributes = %w{name username email gender identity faculty program year_of_study student_id created_at}
    @users.to_csv(*attributes)
  end

  def self.lab_session_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @labs = LabSession.between_dates_picked(start_date, end_date)
    column = []
    column << ["Visitors of CEED facilities in the past week"] <<[]
    column << ["Sign-in time", "Name", "Email", "Gender","Identity", "Faculty", "Program", "Space"]
    @labs.each do |lab|
      row = []
      row << lab.sign_in_time
      row << lab.user.name << lab.user.email << lab.user.gender << lab.user.identity << lab.user.faculty << lab.user.program
      row << Space.find(lab.space.id).name
      column << row
    end
    column << [] << ["Total visitors this week:", @labs.length] << ["# of Unique Visits:", @labs.distinct.count(:user_id)]
    @labs.to_csv(column)
  end

  # *******FIX THIS
  def self.unique_visitors_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @labs = LabSession.between_dates_picked(start_date, end_date)
    @unique_visits = @labs.select('DISTINCT user_id')
    column = []
    column << ["Unique visitors of CEED facilities in the past week"] <<[]
    column << ["Sign-in time", "Name", "Email", "Gender","Identity", "Faculty", "Program", "Space"]
    @unique_visits.each do |lab|
      row = []
      row << lab.user.name << lab.user.email << lab.user.gender << lab.user.identity << lab.user.faculty << lab.user.program
      row << Space.find(lab.space.id).name
      column << row
    end
    column << [] << ["# of Unique Visitors this week:", @labs.distinct.count(:user_id)]
    @unique_visits.to_csv(column)
  end

  def self.faculty_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
      @users = User.between_dates_picked(start_date, end_date)
      @faculty_freq = @users.where.not('faculty' => nil).group(:faculty).count(:faculty)
      @no_faculty = @users.where('faculty' => nil)
      CSV.generate do |csv|
        csv << ["Faculty distribution of users signed up to MakerRepo in the past week"]
        csv << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
        csv << @faculty_freq.keys
        csv << @faculty_freq.values

        csv << ["No faculty specified (faculty/community members):", @no_faculty.length]
        csv << [] << ["Total users:", @users.length]

      end
  end

  def self.gender_frequesncy_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @users = User.between_dates_picked(start_date, end_date)
    @gender_freq = @users.group(:gender).count(:gender)
    CSV.generate do |csv|
      csv << @gender_freq.keys
      csv << @gender_freq.values
    end
  end

  def self.training_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @certifications = Certification.between_dates_picked(start_date, end_date)

    column = []
    column << ["TRAINING ID", "STUDENT ID", "NAME", "EMAIL", "CERTIFICATION TYPE", "CERTIFICATION DATE", "INSTRUCTOR", "COURSE", "WORKSHOP"]

    @certifications.each do |certification|
      row = []
      row << certification.id << certification.user.student_id << certification.user.name << certification.user.email << certification.training
      row << certification.created_at.strftime('%a, %d %b %Y %H:%M') <<  User.find(certification.training_session.user_id).name << certification.training_session.course << Space.find(certification.training_session.training.space_id).name
      column << row
    end
    @certifications.to_csv(column)
  end

  def self.project_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @repositories = Repository.between_dates_picked(start_date, end_date)
    column = []
    column << ["title", "owner", "url", "categories"]

    @repositories.each do |repository|
      row = []
      row << repository.title << repository.user.name
      row << Rails.application.routes.url_helpers.repository_path(slug: repository.slug, user_username: repository.user_username)

      @categories = repository.categories
      @categories.each do |category|
        row << category.name
      end

      column << row
    end
    @repositories.to_csv(column)
  end


  def self.training_session_report(id)
    @session = TrainingSession.find(id)
    @students = @session.users

    column = []
    column << ["Training Type:", Training.find(@session.training_id).name] << ["Location: ", Space.find(Training.find(@session.training_id).space_id).name]
    column << ["Date:", @session.created_at.strftime('%a, %d %b %Y %H:%M')] << ["Trainer:", @session.user.name] << ["Course:", @session.course]
    column << ["Total Number of Trainees:" , @students.length]
    column << [] << ["Trainees"]<< ["Name", "Email"]
    @students.each do |student|
      row = []
      row << student.name << student.email
      column << row
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end

  def self.present_users_report(id, user_id)
    @space = Space.find(id)
    @staff = User.find(user_id)
    @users = @space.signed_in_users

    column = []
    column << ["Space: ", @space.name]
    column << ["Staff: ", @staff.name]
    column << ["Date:", Time.zone.now.strftime('%a, %d %b %Y at %H:%M')]
    column << [] << ["Users"]<< ["Name", "Email", "Student number"]
    @users.each do |user|
      row = []
      row << user.name << user.email
      row << (user.student_id || '')
      column << row
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end

end
