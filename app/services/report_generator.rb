class ReportGenerator
  #region Date Range Reports

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

      self.table_header(sheet, ["Identity", "Distinct Users", "Total Visits"])

      space_details[:identities].each do |identity_name, space|
        sheet.add_row [identity_name, space[:unique], space[:total]]
      end

      sheet.add_row # spacing

      self.table_header(sheet, ["Faculty", "Distinct Users", "Total Visits"])

      space_details[:faculties].each do |faculty_name, space|
        sheet.add_row [faculty_name, space[:unique], space[:total]]
      end

      sheet.add_row # spacing

      self.table_header(sheet, ["Identity", "Faculty", "Distinct Users", "Total Visits"])
      space_details[:identities].each do |identity_name, identity|
        start_index = sheet.rows.last.row_index + 1

        identity[:faculties].each do |faculty_name, faculty|
          sheet.add_row [ identity_name, faculty_name, faculty[:unique], faculty[:total] ], :style => [merge_cell]
        end

        end_index = sheet.rows.last.row_index

        sheet.merge_cells("A#{start_index + 1}:A#{end_index + 1}")
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

      self.table_header(sheet, [ "Training", "Session Count", "Total Attendees" ])

      trainings[:training_types].each do |_, training_type|
        sheet.add_row [
                        training_type[:name],
                        training_type[:count],
                        training_type[:total_attendees]
                      ]
      end

      sheet.add_row # spacing

      self.table_header(sheet, [ "Training", "Level", "Course", "Instructor", "Date", "Facility", "Attendee Count" ])

      trainings[:training_sessions].each do |row|
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

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_new_users_report(start_date, end_date)
    users = User.between_dates_picked(start_date, end_date)

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      self.title(sheet, "New Users")

      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      self.title(sheet, "Overview")

      groups = users.group_by { |user| user.identity }

      groups.each do |group_name, values|
        sheet.add_row [ group_name, values.length ]
      end

      sheet.add_row # spacing

      self.table_header(sheet, [ "Name", "Username", "Email", "Gender", "Identity", "Faculty", "Year of Study", "Student ID", "Joined on" ])

      users.each do |user|
        sheet.add_row [
                        user.name,
                        user.username,
                        user.email,
                        user.gender,
                        user.identity,
                        user.faculty,
                        user.year_of_study,
                        user.student_id,
                        user.created_at.localtime.strftime("%Y-%m-%d %H:%M")
                      ]
      end
    end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_training_attendees_report(start_date, end_date)
    certifications = Certification.includes({ :training_session => [ :user, :training, :space ] }, :user).where('created_at' => start_date..end_date).order('spaces.name', 'training_sessions.created_at', 'users_certifications.name').group_by { |item| item.training_session.space.id }

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      merge_cell = sheet.styles.add_style :alignment => { :vertical => :center }

      self.title(sheet, "Training Attendees")

      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      certifications.each do |space, space_certifications|
        self.title(sheet, space_certifications[0].training_session.space.name)
        self.table_header(sheet, [ "Certification Type", "Certification Date", "Instructor", "Course", "Facility", "Student ID", "Name", "Email Address" ])

        start_index = sheet.rows.last.row_index + 2
        last_training_session_id = nil

        space_certifications.each do |certification|
          if last_training_session_id != certification.training_session.id and not last_training_session_id.nil?
            end_index = sheet.rows.last.row_index + 1

            if start_index < end_index
              sheet.merge_cells("A#{start_index}:A#{end_index}")
              sheet.merge_cells("B#{start_index}:B#{end_index}")
              sheet.merge_cells("C#{start_index}:C#{end_index}")
              sheet.merge_cells("D#{start_index}:D#{end_index}")
              sheet.merge_cells("E#{start_index}:E#{end_index}")
            end

            start_index = sheet.rows.last.row_index + 2
          end

          sheet.add_row [
                          certification.training_session.training.name,
                          certification.training_session.created_at.strftime('%Y-%m-%d %H:%M'),
                          certification.training_session.user.name,
                          certification.training_session.course,
                          certification.training_session.space.name,
                          certification.user.student_id,
                          certification.user.name,
                          certification.user.email
                        ], style: [merge_cell, merge_cell, merge_cell, merge_cell, merge_cell]

          last_training_session_id = certification.training_session.id
        end

        sheet.add_row # spacing
      end
    end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_new_projects_report(start_date, end_date)
    repositories = Repository.where('created_at' => start_date..end_date).includes(:users, :categories)

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      self.title(sheet, "New Projects")

      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      self.table_header(sheet, [ "Title", "Users", "URL", "Categories" ])

      repositories.each do |repository|
        sheet.add_row [
                        repository.title,
                        (repository.users.map { |user| user.name }).join(', '),
                        Rails.application.routes.url_helpers.repository_path(slug: repository.slug, user_username: repository.user_username),
                        (repository.categories.map { |category| category.name }).join(', ')
                      ]
      end
    end

    spreadsheet
  end

  # @param [Integer] id
  def self.generate_training_session_report(id)
    session = TrainingSession.includes(:user, :users, :space, :training).find(id)

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      self.title(sheet, "Training Session")

      sheet.add_row ["Training Type", session.training.name]
      sheet.add_row ["Location", session.space.name]
      sheet.add_row ["Date", session.created_at.strftime("%Y-%m-%d %H:%M")]
      sheet.add_row ["Instructor", session.user.name]
      sheet.add_row ["Course", session.course]
      sheet.add_row ["Number of Trainees", session.users.length]

      sheet.add_row # spacing

      self.table_header(sheet, [ "Name", "Email", "Student Number" ])

      session.users.each do |student|
        sheet.add_row [ student.name, student.email, student.student_id ]
      end
    end

    spreadsheet
  end

  # @param [Integer] id
  def self.generate_space_present_users_report(id)
    lab_sessions = LabSession.includes(:user).joins(:user).where('space_id' => id).where('sign_in_time < ?', DateTime.now).where('sign_out_time > ?', DateTime.now)

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet(name: "Report") do |sheet|
      self.title(sheet, "Present Users")

      sheet.add_row ["Date", DateTime.now.strftime("%Y-%m-%d %H:%M:%S")]

      sheet.add_row # spacing

      self.table_header(sheet, [ "Name", "Email", "Student Number" ])

      lab_sessions.each do |lab_session|
        sheet.add_row [ lab_session.user.name, lab_session.user.email, lab_session.user.student_id ]
      end
    end

    spreadsheet
  end

  #endregion

  #region Aggregation over multiple periods

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_peak_hours_report(start_date, end_date)
    ls = LabSession.arel_table

    result = ActiveRecord::Base.connection.exec_query(ls.project(
      ls['sign_in_time'].extract('YEAR').as('year'),
      ls['sign_in_time'].extract('MONTH').as('month'),
      ls['sign_in_time'].extract('DAY').as('day'),
      ls['sign_in_time'].extract('HOUR').as('hour'),
      Arel.star.count.as('total_visits')
    ).from(ls).where(ls['sign_in_time'].between(start_date..end_date)).group('year', 'month', 'day', 'hour').to_sql)

    visits_by_hour = {}
    min_hour = 23
    max_hour = 0

    result.each do |row|
      year = row['year'].to_i
      month = row['month'].to_i
      day = row['day'].to_i
      hour = row['hour'].to_i
      total_visits = row['total_visits'].to_i

      date = DateTime.new(year, month, day, hour).localtime

      min_hour = [min_hour, date.hour].min
      max_hour = [max_hour, date.hour].max
      
      unless visits_by_hour[date.year]
        visits_by_hour[date.year] = {}
      end

      unless visits_by_hour[date.year][date.month]
        visits_by_hour[date.year][date.month] = {}
      end

      unless visits_by_hour[date.year][date.month][date.day]
        visits_by_hour[date.year][date.month][date.day] = {}
      end

      visits_by_hour[date.year][date.month][date.day][date.hour] = total_visits
    end

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet do |sheet|
      self.title(sheet, 'Visitors by Hour')
      sheet.add_row ['From', start_date.strftime('%Y-%m-%d')]
      sheet.add_row ['To', end_date.strftime('%Y-%m-%d')]
      sheet.add_row # spacing
      
      header = ['Date']

      (min_hour..max_hour).each do |hour|
        header << '%02i:00' % hour
      end

      self.table_header(sheet, header)

      (start_date..end_date).each do |date|
        row = [date.strftime('%Y-%m-%d')]

        (min_hour..max_hour).each do |hour|
          if visits_by_hour[date.year] and visits_by_hour[date.year][date.month] and visits_by_hour[date.year][date.month][date.day] and visits_by_hour[date.year][date.month][date.day][hour]
            row << visits_by_hour[date.year][date.month][date.day][hour]
          else
            row << 0
          end
        end

        sheet.add_row row
      end
    end

    spreadsheet
  end

  #endregion

  #region Non-migrated reports

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

  # old helper methods

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
      :spaces => {},
      :identities => {},
      :faculties => {},
      :genders => {}
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

      unless organized[:identities][identity]
        organized[:identities][identity] = { :unique => 0, :total => 0, :faculties => {} }
      end

      unless organized[:identities][identity][:faculties][faculty]
        organized[:identities][identity][:faculties][faculty] = { :unique => 0, :total => 0 }
      end

      unless organized[:faculties][faculty]
        organized[:faculties][faculty] = { :unique => 0, :total => 0 }
      end

      unless organized[:genders][gender]
        organized[:genders][gender] = { :unique => 0, :total => 0 }
      end

      unique = row["unique_visitors"].to_i
      total = row["total_visits"].to_i

      organized[:unique] += unique
      organized[:total] += total

      organized[:identities][identity][:unique] += unique
      organized[:identities][identity][:total] += total

      organized[:identities][identity][:faculties][faculty][:unique] += unique
      organized[:identities][identity][:faculties][faculty][:total] += total

      organized[:faculties][faculty][:unique] += unique
      organized[:faculties][faculty][:total] += total

      organized[:genders][gender][:unique] += unique
      organized[:genders][gender][:total] += total

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
                                     t[:id].minimum.as("training_id"),
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

    result = {
      :training_sessions => [],
      :training_types => {}
    }

    ActiveRecord::Base.connection.exec_query(query).each do |row|
      result[:training_sessions] << {
        :training_name => row["training_name"],
        :training_level => row["training_level"],
        :course_name => row["course_name"],
        :instructor_name => row["instructor_name"],
        :date => DateTime.strptime(row["date"], "%Y-%m-%d %H:%M:%S"),
        :facility => row["space_name"],
        :attendee_count => row["attendee_count"].to_i
      }

      unless result[:training_types][row["training_id"]]
        result[:training_types][row["training_id"]] = {
          :name => row["training_name"],
          :count => 0,
          :total_attendees => 0
        }
      end

      result[:training_types][row["training_id"]][:count] += 1
      result[:training_types][row["training_id"]][:total_attendees] += row["attendee_count"].to_i
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
