class ReportGenerator
  #region Reports

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_visitors_report(start_date, end_date)
    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      merge_cell = sheet.styles.add_style :alignment => { :vertical => :center }

      self.title(sheet, "Visitors")
      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      space_details = self.get_visitors(start_date, end_date)

      #region Overview
      self.title(sheet, "Overview")
      self.table_header(sheet, ["Space", "Distinct Users", "Total Visits"])

      space_details[:spaces].each do |space_name, space|
        sheet.add_row [space_name, space[:unique], space[:total]]
      end

      sheet.add_row # spacing
      #endregion

      #region Per-space details
      space_details[:spaces].each do |space_name, space_detail|
        self.title(sheet, space_name)

        self.table_header(sheet, ["Identity", "Distinct Users", "Total Visits"])
        space_detail[:identities].each do |identity_name, identity|
          sheet.add_row [ identity_name, identity[:unique], identity[:total] ]
        end

        sheet.add_row # spacing

        self.table_header(sheet, ["Faculty", "Distinct Users", "Total Visits"])
        space_detail[:faculties].each do |faculty_name, faculty|
          sheet.add_row [ faculty_name, faculty[:unique], faculty[:total] ]
        end

        sheet.add_row # spacing

        self.table_header(sheet, ["Identity", "Faculty", "Distinct Users", "Total Visits"])
        space_detail[:identities].each do |identity_name, identity|
          start_index = sheet.rows.last.row_index + 1

          identity[:faculties].each do |faculty_name, faculty|
            sheet.add_row [ identity_name, faculty_name, faculty[:unique], faculty[:total] ], :style => [merge_cell]
          end

          end_index = sheet.rows.last.row_index

          sheet.merge_cells("A#{start_index + 1}:A#{end_index + 1}")
        end

        sheet.add_row # spacing

        self.table_header(sheet, ["Gender", "Distinct Users", "Total Visits"])
        space_detail[:genders].each do |gender_name, gender|
          sheet.add_row [ gender_name, gender[:unique], gender[:total] ]
        end

        sheet.add_row # spacing
      end
      #endregion
    end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_trainings_report(start_date, end_date)
    trainings = self.get_trainings(start_date, end_date)

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      self.title(sheet, "Trainings")

      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      self.table_header(sheet, [ "Training", "Level", "Course", "Instructor", "Date", "Facility", "Attendee Count" ])

      trainings.each do |row|
        puts "#{row["date"]}"
        puts "#{DateTime.now}"
        puts "#{DateTime.now.strftime("%Y-%m-%d %H:%M:%S.%6N")}"
        sheet.add_row [
                        row[:training_name],
                        row[:training_level],
                        row[:course_name],
                        row[:instructor_name],
                        row[:date].localtime.strftime("%Y-%m-%d %H:%M"),
                        row[:facility],
                        row[:attendee_count]
                      ]
      end
    end

    spreadsheet
  end

  #endregion

  #region Non-migrated reports

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

  def self.faculty_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)
    @users = User.frequency_between_dates(start_date, end_date)
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
      csv << ["Frequency of users in the Makerspace per faculty"]
      csv << ["Start date:", start_date.strftime('%a, %d %b %Y %H:%M')] << ["End date:", end_date.strftime('%a, %d %b %Y %H:%M')] << [] << []
      csv << ["Engineering", @engineering] << ["Science", @science] << ["Telfer school of Management", @telfer] << ["Arts", @art] << ["Health Sciences", @health]
      csv << ["Medicine", @medicine] << ["Social Sciences", @social] << ["Education", @education] << ["Civil Law", @civil] << ["Common Law", @common]
      csv << ["No faculty specified (faculty/community members):", @no_faculty]
      csv << [] << ["Total users:", @users.length]
    end
  end

  def self.gender_frequency_report(start_date = 1.week.ago.beginning_of_week, end_date = 1.week.ago.end_of_week)

    @users = User.frequency_between_dates(start_date, end_date)
    @gender_freq = @users.where.not('gender' => nil).where.not('gender' => 'unknown').group(:gender).count(:gender)
    @null = @users.where('gender' => nil)
    @unknown = @users.where('gender' => 'unknown')

    CSV.generate do |csv|
      csv << ["Frequency of users in the Makerspace per gender"]
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
      row << certification.user.student_id << certification.user.name << certification.user.email << certification.training.name
      row << certification.created_at.strftime('%a, %d %b %Y %H:%M') <<  User.find(certification.training_session.user_id).name << certification.training_session.course << certification.training_session.space.name
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
    column << ["Training Type:", @session.training.name] << ["Location: ", @session.space.name]
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
    column << ["Month","Day","Sign in Time"]
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

  #Total visits, not unque
  # def self.total_visits_per_term_report
  #   column = []
  #   column << ["Number of students visiting CEED facilities per semester "] <<[]
  #   column << ["Facility", "Fall 2017 Term", "Winter 2018 Term"]
  #   Space.all.each do |space|
  #     row = []
  #     name = space.name
  #     row << name
  #     #Fall
  #     totalVisitFall2017 = space.lab_sessions.where('created_at BETWEEN ? AND ? ', DateTime.new(2017, 9, 1, 00, 00, 0) , DateTime.new(2017, 12, 31, 23, 59, 0)).count
  #     row << totalVisitFall2017
  #
  #     #winter
  #     totalVisitWinter2018 = space.lab_sessions.where('created_at BETWEEN ? AND ? ', DateTime.new(2018, 1, 1, 00, 00, 0) , DateTime.new(2018, 4, 30, 23, 59, 0)).count
  #     row << totalVisitWinter2018
  #
  #     column << row
  #   end
  #
  #   CSV.generate do |csv|
  #     column.each do |row|
  #       csv << row
  #     end
  #   end
  # end

  #unique visits
  def self.total_visits_per_term_report
    column = []
    column << ["Number of students visiting CEED facilities per semester (Unique users)"] <<[]
    column << ["Facility", "Fall 2017 Term", "Winter 2018 Term"]
    Space.all.each do |space|
      row = []
      name = space.name
      row << name
      #Fall
      uniqueVisitFall2017 = space.lab_sessions.where('created_at BETWEEN ? AND ? ', DateTime.new(2017, 9, 1, 00, 00, 0) , DateTime.new(2017, 12, 31, 23, 59, 0)).select('DISTINCT user_id').count
      row << uniqueVisitFall2017

      #winter
      uniqueVisitWinter2018 = space.lab_sessions.where('created_at BETWEEN ? AND ? ', DateTime.new(2018, 1, 1, 00, 00, 0) , DateTime.new(2018, 4, 30, 23, 59, 0)).select('DISTINCT user_id').count
      row << uniqueVisitWinter2018

      column << row
    end
    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end


  def self.unique_visits_detail_report

    fall_2017_begin, fall_2017_end, winter_2018_begin, winter_2018_end, summer_2018_begin, summer_2018_end = ReportGenerator.date_season_range(2017)
    fall_2018_begin, fall_2018_end, winter_2019_begin, winter_2019_end, summer_2019_begin, summer_2019_end = ReportGenerator.date_season_range(2018)

    header = ["Facility", "Fall 2017", "Winter 2018", "Summer 2018", "Fall 2019", "Winter 2019"]

    column = []
    column << ["Detailed informaton of unique users viasiting CEED facilities "]
    column << header

    Space.all.each do |space|
      column << []<< [space.name]

      column << ["Fall 2017 Term"]
      ReportGenerator.create_seasonal_report(fall_2017_begin, fall_2017_end, space, column)

      column << ["Winter 2018 Term"]
      ReportGenerator.create_seasonal_report(winter_2018_begin, winter_2018_end, space, column)

      column << ["Summer 2018 Term"]
      ReportGenerator.create_seasonal_report(summer_2018_begin, summer_2018_end, space, column)

      column << ["Fall 2018 Term"]
      ReportGenerator.create_seasonal_report(fall_2018_begin, fall_2018_end, space, column)

      column << ["Winter 2019 Term"]
      ReportGenerator.create_seasonal_report(winter_2019_begin, winter_2019_end, space, column)
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end

  end

  def self.total_visits_detail_report

    fall_2017_begin, fall_2017_end, winter_2018_begin, winter_2018_end, summer_2018_begin, summer_2018_end = ReportGenerator.date_season_range(2017)
    fall_2018_begin, fall_2018_end, winter_2019_begin, winter_2019_end, summer_2019_begin, summer_2019_end = ReportGenerator.date_season_range(2018)

    header = ["Facility", "Fall 2017", "Winter 2018", "Summer 2018", "Fall 2019", "Winter 2019"]

    column = []
    column << ["Detailed informaton of unique users viasiting CEED facilities "]
    column << header

    Space.all.each do |space|
      column << []<< [space.name]

      column << ["Fall 2017 Term"]
      ReportGenerator.create_seasonal_report_total_visits(fall_2017_begin, fall_2017_end, space, column)

      column << ["Winter 2018 Term"]
      ReportGenerator.create_seasonal_report_total_visits(winter_2018_begin, winter_2018_end, space, column)

      column << ["Summer 2018 Term"]
      ReportGenerator.create_seasonal_report_total_visits(summer_2018_begin, summer_2018_end, space, column)

      column << ["Fall 2018 Term"]
      ReportGenerator.create_seasonal_report_total_visits(fall_2018_begin, fall_2018_end, space, column)

      column << ["Winter 2019 Term"]
      ReportGenerator.create_seasonal_report_total_visits(winter_2019_begin, winter_2019_end, space, column)
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end

  end

  def self.date_season_range(year)
    begin_fall = DateTime.new(year, 9, 1).beginning_of_day
    end_fall = DateTime.new(year,12, 31).end_of_day
    begin_winter = DateTime.new(year+1, 1, 1).beginning_of_day
    end_winter = DateTime.new(year+1,4, 30).end_of_day
    begin_summer = DateTime.new(year+1, 5, 1).beginning_of_day
    end_summer = DateTime.new(year+1,8, 31).end_of_day
    return begin_fall, end_fall, begin_winter, end_winter, begin_summer, end_summer
  end

  def self.create_seasonal_report(season_begin, season_end, space, column)
    uniqueVisitSeasonYear = space.lab_sessions.where('created_at BETWEEN ? AND ? ', season_begin , season_end).select('DISTINCT user_id')
    total = uniqueVisitSeasonYear.count
    program = []
    faculty = []
    gender = []
    identity = []
    column << ["TOTAL", total]
    uniqueVisitSeasonYear.each do |lab|
      user = User.find_by_id(lab.user_id)
      program << user.program
      faculty << user.faculty
      gender << user.gender
      identity << user.identity
    end

    column << [] << ["Gender"]
    gendersAll = Hash[gender.group_by {|x| x}.map {|k,v| [k,v.count]}]

    gendersAll.each do |gender|
      column << [gender[0], gender[1]]
    end
    column << [] << ["Faculty"]
    facultyAll = Hash[faculty.group_by {|x| x}.map {|k,v| [k,v.count]}]

    facultyAll.each do |faculty|
      column << [faculty[0], faculty[1]]
    end

    column << [] << ["Program"]
    programsAll = Hash[program.group_by {|x| x}.map {|k,v| [k,v.count]}]

    programsAll.each do |program|
      column << [program[0], program[1]]
    end

    column << [] << ["Identity"]
    identityAll = Hash[identity.group_by {|x| x}.map {|k,v| [k,v.count]}]

    identityAll.each do |identity|
      column << [identity[0], identity[1]]
    end
  end

  def self.create_seasonal_report_total_visits(season_begin, season_end, space, column)
    uniqueVisitSeasonYear = space.lab_sessions.where('created_at BETWEEN ? AND ? ', season_begin , season_end)
    total = uniqueVisitSeasonYear.count
    program = []
    faculty = []
    gender = []
    identity = []
    column << ["TOTAL", total]
    uniqueVisitSeasonYear.each do |lab|
      user = User.find_by_id(lab.user_id)
      program << user.program
      faculty << user.faculty
      gender << user.gender
      identity << user.identity
    end

    column << [] << ["Gender"]
    gendersAll = Hash[gender.group_by {|x| x}.map {|k,v| [k,v.count]}]

    gendersAll.each do |gender|
      column << [gender[0], gender[1]]
    end
    column << [] << ["Faculty"]
    facultyAll = Hash[faculty.group_by {|x| x}.map {|k,v| [k,v.count]}]

    facultyAll.each do |faculty|
      column << [faculty[0], faculty[1]]
    end

    column << [] << ["Program"]
    programsAll = Hash[program.group_by {|x| x}.map {|k,v| [k,v.count]}]

    programsAll.each do |program|
      column << [program[0], program[1]]
    end

    column << [] << ["Identity"]
    identityAll = Hash[identity.group_by {|x| x}.map {|k,v| [k,v.count]}]

    identityAll.each do |identity|
      column << [identity[0], identity[1]]
    end
  end

  def self.unique_visits_ceed
    fall_2017_begin, fall_2017_end, winter_2018_begin, winter_2018_end, summer_2018_begin, summer_2018_end = ReportGenerator.date_season_range(2017)
    fall_2018_begin, fall_2018_end, winter_2019_begin, winter_2019_end, summer_2019_begin, summer_2019_end = ReportGenerator.date_season_range(2018)
    column = []
    column << ["Unique visitors in all CEED facilities "]

    column << ["Fall 2017 Term", ReportGenerator.number_ceed_visits(fall_2017_begin, fall_2017_end)]
    column << ["Winter 2018 Term", ReportGenerator.number_ceed_visits(winter_2018_begin, winter_2018_end)]
    column << ["Summer 2018 Term", ReportGenerator.number_ceed_visits(summer_2018_begin, summer_2018_end)]
    column << ["Fall 2018 Term", ReportGenerator.number_ceed_visits(fall_2018_begin, fall_2018_end)]
    column << ["Winter 2019 Term", ReportGenerator.number_ceed_visits(winter_2019_begin, winter_2019_end)]

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end

  end

  def self.number_ceed_visits(season_begin, season_end)
    return LabSession.where('created_at BETWEEN ? AND ? ', season_begin , season_end).select('DISTINCT user_id').count
  end

  def self.seasonal_certification_report
    fall_2017_begin, fall_2017_end, winter_2018_begin, winter_2018_end, summer_2018_begin, summer_2018_end = ReportGenerator.date_season_range(2017)
    fall_2018_begin, fall_2018_end, winter_2019_begin, winter_2019_end, summer_2019_begin, summer_2019_end = ReportGenerator.date_season_range(2018)

    column = []
    column << ["Number of TOTAL/Unique Certifications per Term per Space"]

    Space.find_each do |space|
      column << [] << [space.name]
      column << [] << ["Total certifications", "Unique Certifications"]
      column << ["Fall 2017 Term", ReportGenerator.number_of_certification(fall_2017_begin, fall_2017_end, space)]
      column << ["Winter 2018 Term", ReportGenerator.number_of_certification(winter_2018_begin, winter_2018_end, space)]
      column << ["Summer 2018 Term", ReportGenerator.number_of_certification(summer_2018_begin, summer_2018_end, space)]
      column << ["Fall 2018 Term", ReportGenerator.number_of_certification(fall_2018_begin, fall_2018_end, space)]
      column << ["Winter 2019 Term", ReportGenerator.number_of_certification(winter_2019_begin, winter_2019_end, space)]
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end

  def self.number_of_certification(date_begin, date_end, space)
    certifications = Certification.joins(:space).where("spaces.name = ?", space.name).where('certifications.created_at BETWEEN ? AND ? ', date_begin , date_end)
    return certifications.count, certifications.select('DISTINCT certifications.user_id').count
  end

  def self.seasonal_training_report
    fall_2017_begin, fall_2017_end, winter_2018_begin, winter_2018_end, summer_2018_begin, summer_2018_end = ReportGenerator.date_season_range(2017)
    fall_2018_begin, fall_2018_end, winter_2019_begin, winter_2019_end, summer_2019_begin, summer_2019_end = ReportGenerator.date_season_range(2018)

    column = []
    column << ["Number of Trainings per Term per Space"]

    Space.find_each do |space|
      column << [] << [space.name]
      column << ["Fall 2017 Term", ReportGenerator.number_of_trainings(fall_2017_begin, fall_2017_end, space)]
      column << ["Winter 2018 Term", ReportGenerator.number_of_trainings(winter_2018_begin, winter_2018_end, space)]
      column << ["Summer 2018 Term", ReportGenerator.number_of_trainings(summer_2018_begin, summer_2018_end, space)]
      column << ["Fall 2018 Term", ReportGenerator.number_of_trainings(fall_2018_begin, fall_2018_end, space)]
      column << ["Winter 2019 Term", ReportGenerator.number_of_trainings(winter_2019_begin, winter_2019_end, space)]
    end

    CSV.generate do |csv|
      column.each do |row|
        csv << row
      end
    end
  end

  def self.number_of_trainings(date_begin, date_end, space)
    count = 0
    TrainingSession.joins(:space).where("spaces.name = ?", space.name).where('training_sessions.created_at BETWEEN ? AND ? ', date_begin , date_end).find_each do |ts|
      if ts.completed?
        count += 1
      end
    end
    return count
    # return TrainingSession.joins(:space).where("spaces.name = ?", space.name).where('training_sessions.created_at BETWEEN ? AND ? ', date_begin , date_end).count
  end

  #endregion

  private

  #region Database helpers

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_visitors(start_date, end_date)
    g = Arel::Table.new("g")
    ls = LabSession.arel_table
    u = User.arel_table
    s = Space.arel_table

    result = ActiveRecord::Base.connection.exec_query(g.project([
      g[:space_name].minimum.as("space_name"), g[:identity], g[:faculty], g[:gender], Arel.star.count.as("unique_visitors"), g[:count].sum.as("total_visits")
    ])
    .from(
      LabSession.select([
        ls[:space_id], s[:name].minimum.as("space_name"), u[:identity], u[:faculty], u[:gender], Arel.star.count
      ])
      .joins(ls.join(u).on(u[:id].eq(ls[:user_id])).join_sources)
      .joins(ls.join(s).on(s[:id].eq(ls[:space_id])).join_sources)
      .where(ls[:sign_in_time].between(start_date..end_date))
      .group(ls[:space_id], ls[:user_id], u[:faculty], u[:identity], u[:gender])
      .as(g.name))
    .order(g[:space_name].minimum, g[:identity], g[:faculty], g[:gender])
    .group(g[:space_id], g[:identity], g[:faculty], g[:gender]).to_sql)

    # shove everything into a hash
    organized = {
      :unique => 0,
      :total => 0,
      :spaces => {}
    }

    result.each do |row|
      space_name = row["space_name"]
      faculty = row["faculty"].blank? ? "Unknown" : row["faculty"]
      gender = row["gender"]

      case row["identity"]
      when "undergrad"
        identity = "Undergraduate"
      when "grad"
        identity = "Graduate"
      when "faculty_member"
        identity = "Faculty Member"
      when "community_member"
        identity = "Community Member"
      else
        identity = "Unknown"
      end

      unless organized[:spaces][space_name]
        organized[:spaces][space_name] = {
          :unique => 0,
          :total => 0,
          :identities => {},
          :faculties => {},
          :genders => {}
        }
      end

      unless organized[:spaces][space_name][:identities][identity]
        organized[:spaces][space_name][:identities][identity] = { :unique => 0, :total => 0, :faculties => {} }
      end

      unless organized[:spaces][space_name][:identities][identity][:faculties][faculty]
        organized[:spaces][space_name][:identities][identity][:faculties][faculty] = { :unique => 0, :total => 0 }
      end

      unless organized[:spaces][space_name][:faculties][faculty]
        organized[:spaces][space_name][:faculties][faculty] = { :unique => 0, :total => 0 }
      end

      unless organized[:spaces][space_name][:genders][gender]
        organized[:spaces][space_name][:genders][gender] = { :unique => 0, :total => 0 }
      end

      unique = row["unique_visitors"].to_i
      total = row["total_visits"].to_i

      organized[:unique] += unique
      organized[:total] += total

      organized[:spaces][space_name][:unique] += unique
      organized[:spaces][space_name][:total] += total

      organized[:spaces][space_name][:identities][identity][:unique] += unique
      organized[:spaces][space_name][:identities][identity][:total] += total

      organized[:spaces][space_name][:identities][identity][:faculties][faculty][:unique] += unique
      organized[:spaces][space_name][:identities][identity][:faculties][faculty][:total] += total

      organized[:spaces][space_name][:faculties][faculty][:unique] += unique
      organized[:spaces][space_name][:faculties][faculty][:total] += total

      organized[:spaces][space_name][:genders][gender][:unique] += unique
      organized[:spaces][space_name][:genders][gender][:total] += total
    end

    organized
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_trainings(start_date, end_date)
    t = Training.arel_table
    ts = TrainingSession.arel_table
    tsu = Arel::Table.new(:training_sessions_users)
    u = User.arel_table
    uu = User.arel_table.alias("trainers")
    s = Space.arel_table

    query = TrainingSession.select([
                                     t[:name].minimum.as("training_name"),
                                     ts[:level].minimum.as("training_level"),
                                     ts[:course].minimum.as("course_name"),
                                     uu[:name].minimum.as("instructor_name"),
                                     ts[:created_at].minimum.as("date"),
                                     s[:name].minimum.as("space_name"),
                                     Arel.star.count.as("attendee_count")
                                   ])
              .where(ts[:created_at].between(start_date..end_date))
              .joins(ts.join(t).on(t[:id].eq(ts[:training_id])).join_sources)
              .joins(ts.join(tsu).on(ts[:id].eq(tsu[:training_session_id])).join_sources)
              .joins(ts.join(u).on(u[:id].eq(tsu[:user_id])).join_sources)
              .joins(ts.join(uu).on(uu[:id].eq(ts[:user_id])).join_sources)
              .joins(ts.join(s).on(s[:id].eq(ts[:space_id])).join_sources)
              .group(ts[:id])
              .order(ts[:created_at].minimum).to_sql

    result = []

    ActiveRecord::Base.connection.exec_query(query).each do |row|
      result << {
        :training_name => row["training_name"],
        :training_level => row["training_level"],
        :course_name => row["course_name"],
        :instructor_name => row["instructor_name"],
        :date => DateTime.strptime(row["date"], "%Y-%m-%d %H:%M:%S"),
        :facility => row["space_name"],
        :attendee_count => row["attendee_count"].to_i
      }
    end

    result
  end

  #endregion

  #region Axlsx helpers

  # @param [Axlsx::Worksheet] worksheet
  # @param [String] title
  def self.title(worksheet, title)
    worksheet.add_row [title], b: true, u: true
  end

  # @param [Axlsx::Worksheet] worksheet
  # @param [Array<String>] headers
  def self.table_header(worksheet, headers)
    worksheet.add_row headers, b: true
  end

  #endregion

end
