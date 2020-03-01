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
