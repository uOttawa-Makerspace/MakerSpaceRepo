class ReportGenerator
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

  private

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

end
