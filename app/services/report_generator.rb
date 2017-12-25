class ReportGenerator

  def self.new_user_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @users = User.between_dates_picked(start_date, end_date)
    column = []
    column << ["New users signed up to makerepo"]
    column << ["Start Date", start_date.strftime('%a, %d %b %Y %H:%M')]
    column << ["End Date", end_date.strftime('%a, %d %b %Y %H:%M')]

    column << [] << ["Name", "Username", "Email", "Gender", "Identity", "Faculty","Year of Study","Student ID","Created at"]
    @users.each do |user|
      row = []
      row << user.name << user.username << user.email << user.gender << user.identity << user.faculty << user.year_of_study << user.student_id << user.created_at
      column << row
    end
    column << [] << ["Total new users:", @users.length]
    column << ["Number of Grads:", @users.where(identity: 'grad').length]
    column << ["Number of Undergrads:", @users.where(identity: 'undergrad').length]
    column << ["Number of Faculty members:", @users.where(identity: 'faculty_member').length]
    column << ["Number of Community members:", @users.where(identity: 'community_member').length]
    column << ["Other (unspecified)", @users.where.not(identity: ['grad', 'undergrad', 'faculty_member', 'community_member']).length + @users.where(identity: nil).length ]
    @users.to_csv(column)
  end

  #visitors
  def self.lab_session_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @labs = LabSession.between_dates_picked(start_date, end_date)
    column = []
    column << ["Visitors of CEED facilities (Total visits)"]
    column << ["Start Date", start_date.strftime('%a, %d %b %Y %H:%M')]
    column << ["End Date", end_date.strftime('%a, %d %b %Y %H:%M')] <<[]
    column << ["Sign-in time", "Name", "Email", "Gender","Identity", "Faculty", "Space"]
    @labs.each do |lab|
      row = []
      row << lab.sign_in_time
      row << lab.user.name << lab.user.email << lab.user.gender << lab.user.identity << lab.user.faculty
      row << Space.find(lab.space.id).name
      column << row
    end

    column << [] << [] << ["Total visitors:", @labs.length] << ["# of Unique Visits:", @labs.distinct.count(:user_id)]

    column << []<< ["Visitors visited these spaces:"] << ["Space", "Number of visitors"]

    @spaces = @labs.group(:space_id).count(:space_id)
    @spaces.each do |space|
      column << [Space.find(space[0]).name, space[1]]
    end

    @visitors = @labs.select('DISTINCT user_id')
    array = []
    @visitors.each do |visitor|
      array << User.find(visitor.user_id).identity
    end
    column << [] << ["Classification based on identity"] << ["Identity", "Count"]
    identities = Hash[array.group_by {|x| x}.map {|k,v| [k,v.count]}]

    identities.each do |identity|
      column << [identity[0], identity[1]]
    end

    column << ["Note: 'unknown' identity means the visitor is an old user and has not updated his/her profile"]

    @labs.to_csv(column)
  end

  def self.unique_visitors_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @labs = LabSession.between_dates_picked(start_date, end_date)
    @unique_visits = @labs.select('DISTINCT user_id')
    column = []
    column << ["Unique visitors of CEED facilities"]
    column << ["Start Date", start_date.strftime('%a, %d %b %Y %H:%M')]
    column << ["End Date", end_date.strftime('%a, %d %b %Y %H:%M')] <<[]
    column << ["Name", "Email", "Gender","Identity", "Faculty"]
    @unique_visits.each do |lab|
      row = []
      row << lab.user.name << lab.user.email << lab.user.gender << lab.user.identity << lab.user.faculty
      column << row
    end

    column << [] << ["# of Unique Visitors this week:", @unique_visits.length]

    array = []
    @unique_visits.each do |visit|
      array << User.find(visit.user_id).identity
    end
    column << [] << ["Classification based on identity"] << ["Identity", "Count"]
    identities = Hash[array.group_by {|x| x}.map {|k,v| [k,v.count]}]

    identities.each do |identity|
      column << [identity[0], identity[1]]
    end

    column << ["Note: 'unknown' identity means the visitor is an old user and has not updated his/her profile"]


    @unique_visits.to_csv(column)
  end

  # def self.faculty_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
  #     @users = User.between_dates_picked(start_date, end_date)
  #     #this is not working
  #     @faculty_freq = @users.where.not('faculty' => nil).group(:faculty).count(:faculty)
  #     @no_faculty = @users.where('faculty' => nil)
  #     CSV.generate do |csv|
  #       csv << ["Faculty distribution of users signed up to MakerRepo"]
  #       csv << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
  #       csv << @faculty_freq.keys
  #       csv << @faculty_freq.values
  #
  #       csv << ["No faculty specified (faculty/community members):", @no_faculty.length]
  #       csv << [] << ["Total users:", @users.length]
  #
  #     end
  # end
  def self.faculty_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
      @users = User.between_dates_picked(start_date, end_date)
      @art = @users.where('faculty' => 'Arts').length
      @civil = @users.where('faculty' => 'Civil Law').length
      @common = @users.where('faculty' => 'Common Law').length
      @education = @users.where('faculty' => 'Education').length
      @engineering = @users.where('faculty' => 'Engineering').length
      @health = @users.where('faculty' => 'Health Sciences').length
      @medicine = @users.where('faculty' => 'Medicine').length
      @science = @users.where('faculty' => 'Science').length
      @social = @users.where('faculty' => 'Social Sciences').length
      @telfer = @users.where('faculty' => 'Telfer school of Management').length

      total_faculty = @art + @civil + @common + @education + @engineering + @health + @medicine + @science + @social + @telfer
      @no_faculty = @users.length - total_faculty

      CSV.generate do |csv|
        csv << ["Faculty distribution of users signed up to MakerRepo"]
        csv << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
        csv << ["Engineering", @engineering] << ["Science", @science] << ["Telfer school of Management", @telfer] << ["Arts", @art] << ["Health Sciences", @health]
        csv << ["Medicine", @medicine] << ["Social Sciences", @social] << ["Education", @education] << ["Civil Law", @civil] << ["Common Law", @common]
        csv << ["No faculty specified (faculty/community members):", @no_faculty]
        csv << [] << ["Total users:", @users.length]
      end
  end

  def self.gender_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)

    @users = User.between_dates_picked(start_date, end_date)
    @gender_freq = @users.where.not('gender' => nil).where.not('gender' => 'unknown').group(:gender).count(:gender)
    @null = @users.where('gender' => nil)
    @unknown = @users.where('gender' => 'unknown')

    CSV.generate do |csv|
      csv << ["Gender distribution of users signed up to MakerRepo"]
      csv << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []

      csv << @gender_freq.keys
      csv << @gender_freq.values

      csv << [] << ["Gender not provided (Old user):", @null.length + @unknown.length]
    end
  end

  #all Trainings
  def self.training_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @certifications = Certification.between_dates_picked(start_date, end_date)
    column = []
    column << ["All Trainings"]
    column << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
    column << ["STUDENT ID", "NAME", "EMAIL", "CERTIFICATION TYPE", "CERTIFICATION DATE", "INSTRUCTOR", "COURSE", "WORKSHOP"]

    @certifications.each do |certification|
      row = []
      row << certification.user.student_id << certification.user.name << certification.user.email << certification.training
      row << certification.created_at.strftime('%a, %d %b %Y %H:%M') <<  User.find(certification.training_session.user_id).name << certification.training_session.course << Space.find(certification.training_session.training.space_id).name
      column << row
    end
    @certifications.to_csv(column)
  end

  def self.makerspace_training_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @makerspace_trainings = Training.where('space_id' => (Space.where('name' => 'Makerspace').ids)) #find trainings in makerspace
    column = []
    column << ["Makerspace Trainings"]
    column << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
    column << ["STUDENT ID", "NAME", "EMAIL", "CERTIFICATION TYPE", "CERTIFICATION DATE", "INSTRUCTOR", "COURSE",]
    @total_number_of_users = 0
    @makerspace_trainings.each do |training| #For each training
      @training_sessions = training.training_sessions.between_dates_picked(start_date, end_date) #find training sessions
      @training_sessions.each do |training_session| #each training session has many students
        if training_session.completed? #check if training_session is completed
          @users = training_session.users
          @total_number_of_users += @users.length
          @users.each do |user| #for each student, grab info
            row = []
            row << user.student_id << user.name << user.email << training.name << training_session.created_at.strftime('%a, %d %b %Y %H:%M') << User.find(training_session.user_id).name << training_session.course
            column << row
          end
        end
      end
    end
    column << [] << ["Total Number of Trainees", @total_number_of_users]
    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end
  def self.mtc_training_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @makerspace_trainings = Training.where('space_id' => (Space.where('name' => 'MTC').ids)) #find trainings in makerspace
    column = []
    column << ["MTC Trainings"]
    column << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
    column << ["STUDENT ID", "NAME", "EMAIL", "CERTIFICATION TYPE", "CERTIFICATION DATE", "INSTRUCTOR", "COURSE",]
    @total_number_of_users = 0
    @makerspace_trainings.each do |training| #For each training
      @training_sessions = training.training_sessions.between_dates_picked(start_date, end_date) #find training sessions
      @training_sessions.each do |training_session| #each training session has many students
        if training_session.completed? #check if training_session is completed
          @users = training_session.users
          @total_number_of_users += @users.length
          @users.each do |user| #for each student, grab info
            row = []
            row << user.student_id << user.name << user.email << training.name << training_session.created_at.strftime('%a, %d %b %Y %H:%M') << User.find(training_session.user_id).name << training_session.course
            column << row
          end
        end
      end
    end
    column << [] << ["Total Number of Trainees", @total_number_of_users]
    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
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

  def self.frequency_hours_report(start_date = 1.month.ago.beginning_of_month, end_date = 1.month.ago.end_of_month)
  @lab_sessions = LabSession.between_dates_picked(start_date, end_date)
  @mspaceLabSessions = @lab_sessions.where('space_id' => Space.find_by_name("Makerspace").id)
  column = []
  @mspaceLabSessions.each do |lab_session|
    row = []
    row << lab_session.sign_in_time.strftime('%m') << lab_session.sign_in_time.strftime('%d')<< lab_session.sign_in_time.strftime('%H:%M')

    column << row
  end

  CSV.generate do |csv|
    column.each do |row|
      csv << row
    end
  end
end

end
