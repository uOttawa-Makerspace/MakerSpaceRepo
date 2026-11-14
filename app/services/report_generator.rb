# frozen_string_literal: true

class ReportGenerator
  require "axlsx"

  # What a sheet or title says for a session that has no space.
  UNKNOWN_SPACE = "Unknown"
  # What a cell says for a session whose training or instructor is missing.
  UNKNOWN = "Unknown"
  # The header of the student number column, which follows every column the
  # user tables have always had. Those columns keep their order and headers
  # for the readers that load them by position: the cell under "Student ID"
  # holds the join date (new users) or the attendee name (attendees).
  STUDENT_NUMBER = "Student number"
  # Cell types: text that people entered is written as text (TEXT), so a
  # value that looks like a number, a date or a formula opens as it was
  # entered; a nil type leaves the cell's type to its value. A label row
  # (LABEL_ROW) has its text in the first cell and counts after it.
  TEXT = :string
  LABEL_ROW = [TEXT].freeze
  # A new users line: the six text columns, then the year of study and the
  # join date as before, and the student number as text.
  NEW_USER_TYPES = ([TEXT] * 6 + [nil, nil, nil, TEXT]).freeze
  # An attendee line (see attendee_row): the date and the empty column keep
  # their own types.
  ATTENDEE_TYPES = [TEXT, TEXT, TEXT, nil, TEXT, TEXT, TEXT, nil, TEXT].freeze
  # A trainings line: every column but the date and the attendee count.
  TRAINING_TYPES = [TEXT, TEXT, TEXT, TEXT, nil, TEXT].freeze
  # An identity and faculty line of the visitors sheets.
  IDENTITY_FACULTY_TYPES = [TEXT, nil, nil, nil, nil, TEXT].freeze
  # region Date Range Reports

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_visitors_report(start_date, end_date)
    spreadsheet = Axlsx::Package.new
    spreadsheet.workbook.use_autowidth = true

    all_visits =
      LabSession
        .where(created_at: start_date..end_date)
        .joins(:user, :space)
        .select(
          :"users.id",
          :"users.faculty",
          :"users.gender",
          :"users.identity",
          :"users.program",
          :"users.program",
          :"spaces.name"
        )
        .to_a
    # TODO: use visits[0].attributes to auto populate uniq map
    all_columns = {
      faculty: all_visits.map { |x| x.faculty }.uniq,
      identity: all_visits.map { |x| x.identity }.uniq,
      space: ["Report"] + all_visits.map { |x| x.name }.uniq
    }

    all_columns[:space].each do |space_name|
      spreadsheet
        .workbook
        .add_worksheet(name: space_name) do |sheet|
          merge_cell = sheet.styles.add_style alignment: { vertical: :center }
          grey_cell =
            sheet.styles.add_style bg_color: "dddddd",
                                   alignment: {
                                     vertical: :center
                                   }

          header(sheet, "Visitors", start_date, end_date)
          space_visits =
            (
              if space_name == "Report"
                all_visits
              else
                all_visits.select { |x| x["name"] == space_name }
              end
            )

          # Visits by space, special case if overview
          if space_name == "Report"
            title(sheet, "Overview")
            sheet.add_row ["CEED-Wide unique visitors", all_visits.uniq.count]
            sheet.add_row ["CEED-Wide total visitors", all_visits.count]
          else
            title(sheet, "Report for #{space_name}")
          end

          sheet.add_row # spacing

          # sort by identity
          table_header(
            sheet,
            ["Identity", "Distinct Users", "", "Total Visits"]
          )
          space_visits
            .group_by { |d| User.identity_label(d["identity"]) }
            .each do |identity, counts|
              sheet.add_row [identity, counts.uniq.count, "", counts.count],
                            types: LABEL_ROW
            end

          sheet.add_row # spacing

          # sort by gender
          table_header(sheet, %w[Gender Count])
          space_visits
            .group_by { |x| x["gender"] }
            .sort
            .each do |gender, counts|
              sheet.add_row [gender, counts.uniq.count], types: LABEL_ROW
            end

          sheet.add_row # spacing

          table_header(sheet, ["Faculty", "Distinct Users", "", "Total Visits"])

          # sort by faculty
          space_visits
            .group_by { |d| User.faculty_label(d.faculty) }
            .each do |faculty, counts|
              sheet.add_row [
                              faculty,
                              counts.uniq.count,
                              "",
                              counts.count
                            ],
                            types: LABEL_ROW
            end

          # group by faculty, identity
          sheet.add_row # spacing

          table_header(
            sheet,
            ["Identity", "Distinct Users", "", "Total Visits", "", "Faculty"]
          )
          merge_cell = sheet.styles.add_style alignment: { vertical: :center }
          grey_cell =
            sheet.styles.add_style bg_color: "dddddd",
                                   alignment: {
                                     vertical: :center
                                   }
          toggle_grey = true
          space_visits
            .group_by { |x| User.identity_label(x.identity) }
            .each do |identity, rest|
              start_cell = sheet.rows.last.cells.first.pos # for merging
              rest
                .group_by { |y| User.faculty_label(y.faculty) }
                .each do |faculty, counts|
                  sheet.add_row [
                                  identity,
                                  counts.uniq.count,
                                  "",
                                  counts.count,
                                  "",
                                  faculty
                                ],
                                style: toggle_grey ? grey_cell : merge_cell,
                                types: IDENTITY_FACULTY_TYPES
                end
              end_cell = sheet.rows.last.cells.first.pos
              sheet.merge_cells Axlsx.cell_r(start_cell[0], start_cell[1] + 1) +
                                  ":" + Axlsx.cell_r(end_cell[0], end_cell[1])
              toggle_grey = !toggle_grey
            end

          # FIXME: test if sorting by users.faculty gives different count than
          # users.program.include? engineering. Community users might affect this
          # so also filter by identity == undergrad or grad

          sheet.add_row # spacing

          # group by engineering department
          # Some programs have the BOM, we need to sanitize at input really
          table_header(
            sheet,
            ["Department", "Distinct Users", "", "Total Visits", "", "Level"]
          )
          space_visits
            .group_by { |x| get_program_department(x.program) }
            .each do |program, rest|
              start_cell = sheet.rows.last.cells.first.pos # for merging
              rest
                .group_by { |x| get_study_level(x.program) }
                .sort
                .each do |level, counts|
                  sheet.add_row [
                                  program,
                                  counts.uniq.count,
                                  "",
                                  counts.count,
                                  "",
                                  level
                                ],
                                style: toggle_grey ? grey_cell : merge_cell
                end
              end_cell = sheet.rows.last.cells.first.pos
              sheet.merge_cells Axlsx.cell_r(start_cell[0], start_cell[1] + 1) +
                                  ":" + Axlsx.cell_r(end_cell[0], end_cell[1])
              toggle_grey = !toggle_grey
            end
        end
    end

    spreadsheet
      .workbook
      .add_worksheet(name: "Programs") do |sheet|
        table_header(sheet, ["program", "Distinct Users", "", "Total Visits"])
        all_visits
          .group_by do |x|
            if !x.program.nil? and !x.program&.empty?
              x.program.strip.gsub(/^\W+/, "")
            else
              "None"
            end
          end
          .sort
          .each do |program, counts|
            sheet.add_row [program, counts.uniq.count, "", counts.count],
                          types: LABEL_ROW
          end
      end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_trainings_report(start_date, end_date)
    # TODO: this is wrong, replace it with active queries not raw sql
    trainings = get_trainings(start_date, end_date)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Trainings")

        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        table_header(sheet, ["Training", "Session Count", "Total Attendees"])

        # trainings[:training_types].each do |_, training_type|
        trainings
          .to_a
          .group_by { |d| d["training_name"] }
          .each do |k, training_type|
            sheet.add_row [
                            k,
                            training_type.count,
                            training_type.sum { |d| d["attendee_count"] }
                          ],
                          types: LABEL_ROW
          end

        sheet.add_row # spacing

        table_header(
          sheet,
          [
            "Training",
            "Level",
            "Course",
            "Instructor",
            "Date",
            "Facility",
            "Attendee Count"
          ]
        )

        trainings.each do |row|
          # training = Training.find(row[:training_id])
          # color =
          #   if training.skill_id.present?
          #     if training.skill.name == "Machine Shop Training"
          #       { bg_color: "ed7d31" }
          #     elsif training.skill.name == "Technology Trainings"
          #       { bg_color: "70ad47" }
          #     elsif training.skill.name == "CEED Trainings"
          #       { bg_color: "ffc000" }
          #     else
          #       {}
          #     end
          #   else
          #     {}
          #   end
          # style = sheet.styles.add_style(color)

          sheet.add_row [
                          row["training_name"],
                          row["training_level"],
                          row["course_name"],
                          row["instructor_name"],
                          row["date"].in_time_zone.strftime("%Y-%m-%d %H:%M"),
                          row["space_name"],
                          row["attendee_count"]
                        ],
                        types: TRAINING_TYPES # ,
          # style: [style]
        end
      end

    spreadsheet
  end

  # Fetch certifications, per space
  # FIXME funfact some training sessions aren't marked as completed?
  # We're
  def self.generate_certifications_report(start_date, end_date)
    aggregate_data = get_certifications(start_date, end_date)

    # completed sessions and certs awarded
    # ___________|_______Course 1_______|________Total_________|
    # Topic name | Sessions | Attendees | Sessions | Attendees |
    # ----------------------|-----------|----------|-----------|
    # topic 1    |          |           |          |           |
    # topic 2    |          |           |          |           |
    #
    #

    spreadsheet = Axlsx::Package.new
    spreadsheet.workbook.use_autowidth = true
    # heading_style = spreadsheet.workbook.styles.add_style
    centered_style =
      spreadsheet.workbook.styles.add_style alignment: { horizontal: :center }
    outside_borders =
      spreadsheet.workbook.styles.add_style border: {
                                              style: :thick,
                                              color: "FF000000",
                                              edges: %i[left right top bottom]
                                            }

    # collect categories for easier looping
    spaces = []
    topics = []
    courses = []
    aggregate_data.each do |row|
      spaces << row["space_name"]
      topics << row["name"]
      courses << row["course"]
    end
    # remove dupes, might include nil so put it at top
    spaces =
      spaces
        .uniq
        .sort do |a, b|
          if a && b
            a <=> b
          else
            a ? 1 : -1
          end
        end
        .reverse
    topics = topics.uniq
    courses = courses.uniq # .map { |d| d || "None" }

    (spaces + ["total"]).each do |space|
      space_label = space || UNKNOWN_SPACE
      spreadsheet
        .workbook
        .add_worksheet(name: space_label) do |sheet|
          title(sheet, "Makerepo Certifications report")
          title_string = "Certifications granted in #{space_label}"
          header(sheet, title_string, start_date, end_date)
          sheet.column_widths title_string.length + 2

          # push headers, add space to be merged
          sheet.add_row [""] + courses.map { |d| [d || "Open", ""] }.flatten +
                          ["Total", ""],
                        style: centered_style,
                        types: TEXT
          # merge subheaders
          # Plus the total header
          (courses.count + 1).times do |n|
            n = n * 2 + 1
            # NOTE: Merging non-existent cells is bad.
            # https://github.com/randym/axlsx/issues/189
            sheet.merge_cells sheet.rows.last.cells[(n..n + 1)]
          end

          # add an extra for the topic totals
          sheet.add_row ["Training"] +
                          ["Completed sessions", "Certs awarded"] *
                            (courses.count + 1),
                        style: centered_style

          course_totals = {}
          courses.each { |c| course_totals[c] = { sessions: 0, certs: 0 } }

          # push data, collect totals meanwhile
          topics.each do |topic|
            entry = [topic]
            courses.each do |course|
              # push number of completed sessions and certs
              # for each space, course, topic, get numer of sessions and certs
              # put each result into an array that looks like [[1,2], [3,4]...]
              # then element wise sum each into a final [4, 6]
              this_space =
                aggregate_data
                  .find_all do |d|
                    # get all spaces if doing totals
                    (d["space_name"] == space || space == "total") and
                      d["name"] == topic and d["course"] == course
                  end
                  .map do |d|
                    d.values_at("total_sessions", "total_certifications") # get from each result
                  end
                  .transpose
                  .map(&:sum) # vector sum

              # || [0, 0] # default if not found
              entry += this_space == [] ? [0, 0] : this_space
            end

            # sum sessions
            total_sessions = entry.drop(1).each_slice(2).map(&:first).sum
            total_certs = entry.drop(1).each_slice(2).map(&:last).sum
            entry += [total_sessions, total_certs]

            # finally push row
            sheet.add_row entry, style: centered_style, types: LABEL_ROW
          end

          # push final total row, for each course
          totals_row = ["Total"]
          courses.each do |course|
            course_total =
              aggregate_data
                .find_all do |d|
                  (d["space_name"] == space || space == "total") and
                    d["course"] == course
                end
                .map do |d|
                  d.values_at("total_sessions", "total_certifications")
                end
                .transpose
                .map(&:sum)
            course_total = [0, 0] if course_total == []
            totals_row += course_total
          end

          totals_row += [
            totals_row.drop(1).each_slice(2).map(&:first).sum,
            totals_row.drop(1).each_slice(2).map(&:last).sum
          ]
          sheet.add_row totals_row, style: centered_style
        end
    end
    spreadsheet
  end

  def self.get_new_users(start_date, end_date)
    User.including_deleted.where(created_at: start_date..end_date)
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_new_users_report(start_date, end_date)
    # users = User.between_dates_picked(start_date, end_date)
    # users = User.where(created_at: start_date..end_date)
    users = get_new_users(start_date, end_date)

    # Breakdown by faculty, department (for engineering/non-engineer %), Study level

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Demographics") do |sheet|
        header(sheet, "New Users Breakdown", start_date, end_date)

        sheet.add_row ["Total new users", users.count]
        sheet.add_row

        title(sheet, "Year of Study")
        User
          .years_of_study_in_order(users.group(:year_of_study).count)
          .each { |key, value| sheet.add_row [key, value] }

        sheet.add_row
        title(sheet, "Level of Study")
        push_hash(
          sheet,
          users
            .group(:identity)
            .count
            .each_with_object(Hash.new(0)) do |(identity, count), counts|
              counts[User.identity_label(identity)] += count
            end
        )

        sheet.add_row
        title(sheet, "Gender")
        users
          .group(:gender)
          .count
          .sort
          .each { |key, value| sheet.add_row [key, value], types: LABEL_ROW }
      end

    spreadsheet
      .workbook
      .add_worksheet(name: "Faculties") do |sheet|
        header(sheet, "Users by Faculty, Department", start_date, end_date)

        merge_cell = sheet.styles.add_style alignment: { vertical: :center }
        grey_cell =
          sheet.styles.add_style bg_color: "dddddd",
                                 alignment: {
                                   vertical: :center
                                 }

        # By Study level
        # Engineering/non-engineering

        # By faculty
        title(sheet, "By Faculty")
        table_header(sheet, ["Faculty", "New Users"])
        push_hash(
          sheet,
          users
            .group(:faculty)
            .count
            .each_with_object(Hash.new(0)) do |(faculty, count), counts|
              counts[User.faculty_label(faculty)] += count
            end
        )
        sheet.add_row ["Total", users.count]
        sheet.add_row

        # program summaries as a cross table
        # Count who's in engineering, who's not
        # Count who's in Masters, phd, etc.
        # HACK this is literally just a regex count.
        # Try to categorize programs into a relational database
        # Because I don't believe this is totally accurate
        title(sheet, "By Department")
        table_header(sheet, ["Department", "New Users", "", "Level"])
        toggle_grey = true
        users
          .group_by { |x| get_program_department(x.program) }
          .each do |program, counts|
            start_cell = sheet.rows.last.cells.first.pos # for merging
            counts
              .group_by { |x| get_study_level(x.program) }
              .each do |level, counts|
                sheet.add_row [program, counts.count, "", level],
                              style: toggle_grey ? grey_cell : merge_cell
              end
            toggle_grey = !toggle_grey
            end_cell = sheet.rows.last.cells.first.pos
            sheet.merge_cells Axlsx.cell_r(start_cell[0], start_cell[1] + 1) +
                                ":" + Axlsx.cell_r(end_cell[0], end_cell[1])
          end

        sheet.add_row

        # By program
        programs = users.group(:program).count
        title(sheet, "By program")
        push_hash(
          sheet,
          programs
            .transform_keys { |k| k == "" ? "Blank - No Program" : k }
            .sort_by { |_k, v| [-v] }
        )

        sheet.column_widths 55
      end

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "New Users")

        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        sheet.add_row # spacing
        sheet.add_row # spacing

        male = users.where(gender: "Male").count
        female = users.where(gender: "Female").count
        other = users.where(gender: "Other").count
        prefer_not = users.where(gender: "Prefer not to specify").count
        final_other = other + prefer_not

        sheet.add_chart(
          Axlsx::Pie3DChart,
          rot_x: 90,
          start_at: "D1",
          end_at: "G13",
          grouping: :stacked,
          show_legend: true,
          title: "Gender of new users"
        ) do |chart|
          chart.add_series data: [male, female, final_other],
                           labels: [
                             "Male",
                             "Female",
                             "Other/Prefer not to specify"
                           ],
                           colors: %w[1FC3AA 8624F5 A8A8A8 A8A8A8]
          chart.add_series data: [male, female, final_other],
                           labels: [
                             "Male",
                             "Female",
                             "Other/Prefer not to specify"
                           ],
                           colors: %w[FFFF00 FFFF00 FFFF00]
          chart.d_lbls.show_percent = true
          chart.d_lbls.d_lbl_pos = :bestFit
        end

        sheet.add_row # spacing
        sheet.add_row # spacing
        sheet.add_row # spacing
        sheet.add_row # spacing

        title(sheet, "Overview")

        users
          .group_by(&:identity)
          .each do |identity, values|
            sheet.add_row [identity, values.length], types: LABEL_ROW
          end

        sheet.add_row # spacing

        columns = [
          "Name",
          "Username",
          "Email",
          "Gender",
          "Identity",
          "Faculty",
          "Year of Study",
          "Student ID",
          "Joined on",
          STUDENT_NUMBER
        ]
        table_header(sheet, columns)

        users.each do |user|
          sheet.add_row [
                          user.name,
                          user.username,
                          user.email,
                          user.gender,
                          user.identity,
                          user.faculty,
                          user.year_of_study,
                          user.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M"),
                          nil,
                          user.student_id
                        ],
                        types: NEW_USER_TYPES
        end
      end

    spreadsheet
  end

  # One attendee line, starting under the first header (see STUDENT_NUMBER),
  # with the student number in the last column. A missing attendee name,
  # training or instructor shows Unknown in that cell.
  def self.attendee_row(certification)
    user = certification.user
    [
      user&.name || UNKNOWN,
      user&.email,
      *attendee_session_cells(certification.training_session),
      nil,
      user&.student_id
    ]
  end

  # The training, date, instructor, course and facility cells of an attendee
  # line.
  def self.attendee_session_cells(session)
    [
      session.training&.name_en || UNKNOWN,
      session.created_at.strftime("%Y-%m-%d %H:%M"),
      session.user&.name || UNKNOWN,
      session.course,
      session.space&.name
    ]
  end
  private_class_method :attendee_session_cells
  private_class_method :attendee_row

  def self.generate_training_attendees_report(start_date, end_date)
    certifications =
      Certification
        .includes({ training_session: %i[user training space] }, :user)
        .where(created_at: start_date..end_date)
        .where.not(training_session_id: nil)
        .order(
          "spaces.name",
          "training_sessions.created_at",
          "users_certifications.name"
        )
        .group_by { |item| item.training_session.space&.id or 0 }

    spreadsheet = Axlsx::Package.new

    certifications.each do |_space, space_certifications|
      space_name =
        space_certifications[0].training_session.space&.name || UNKNOWN_SPACE
      spreadsheet
        .workbook
        .add_worksheet(name: "Report - #{space_name}") do |sheet|
          merge_cell = sheet.styles.add_style alignment: { vertical: :center }

          title(sheet, "Training Attendees - #{space_name}")

          sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
          sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
          sheet.add_row # spacing

          columns = [
            "Student ID",
            "Name",
            "Email Address",
            "Certification Type",
            "Certification Date",
            "Instructor",
            "Course",
            "Facility",
            STUDENT_NUMBER
          ]
          table_header(sheet, columns)

          space_certifications.each do |certification|
            sheet.add_row attendee_row(certification), types: ATTENDEE_TYPES
          end

          sheet.add_row #spacing

          one_decimal = sheet.styles.add_style format_code: "0.0"
          month_header = ["Month"]
          month_average = ["Month average of attendees per sessions"]
          calendar_periods(start_date, end_date, :month).each do |month|
            month_header << month.first.strftime("%B")
            month_average << average_attendees_per_session(
              space_certifications,
              month
            )
          end

          table_header(sheet, month_header)
          sheet.add_row month_average, style: one_decimal
          sheet.add_row # spacing

          week_header = ["Week"]
          week_average = ["Week average of attendees per sessions"]
          calendar_periods(start_date, end_date, :week).each do |week|
            week_header << "#{week.first.strftime("%Y-%m-%d")} to #{week.last.strftime("%Y-%m-%d")}"
            week_average << average_attendees_per_session(
              space_certifications,
              week
            )
          end

          table_header(sheet, week_header)
          sheet.add_row week_average, style: one_decimal
          sheet.add_row # spacing
        end
    end

    spreadsheet
  end

  def self.generate_new_projects_report(start_date, end_date)
    repositories =
      Repository
        .where("created_at" => start_date..end_date)
        .includes(:users, :categories, :equipments)
        .preload(:categories, :equipments)

    spreadsheet = Axlsx::Package.new

    # Category|Count
    # --------|-----
    # cat 1   |10
    # cat 2   |20

    # group by category, first find all categories
    # NOTE schema is messed up, yes there's a separate category for each repo
    # category_count = Category.where(created_at: start_date..end_date).group(:name).count
    # category_count = Category.where(created_at: start_date..end_date).joins(:repository).group(:name).count
    # repositories.select(:category).group(:name).count

    category_count = Hash.new(0)
    equipment_count = Hash.new(0)
    repositories.each do |repo|
      repo.categories.each { |cat| category_count[cat.name] += 1 }
      repo.equipments.each { |equip| equipment_count[equip.name] += 1 }
    end

    spreadsheet
      .workbook
      .add_worksheet(name: "Statistics") do |sheet|
        title(sheet, "Various statistics")
        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row ["Total New Projects", repositories.count]

        sheet.add_row # spacing

        title(sheet, "Categories")
        push_hash(sheet, category_count)
        # add total sum
        sheet.add_row ["Total", category_count.values.sum]

        sheet.add_row

        title(sheet, "Equipment usage")
        push_hash(sheet, equipment_count)
        sheet.add_row ["Total", equipment_count.values.sum]

        sheet.add_row

        title(sheet, "Licenses")
        total_licenses = 0
        repositories
          .group(:license)
          .count
          .each do |key, value|
            sheet.add_row [key, value], types: LABEL_ROW
            total_licenses += value
          end
        sheet.add_row ["Total", total_licenses]

        sheet.add_row
        title(sheet, "Share types")
        total_share_type = 0
        repositories
          .group(:share_type)
          .count
          .each do |key, value|
            sheet.add_row [key, value], types: LABEL_ROW
            total_share_type += value
          end
        sheet.add_row ["Total", total_share_type]
      end

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "New Projects")

        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        # FIXME: this sucks, fix it
        # Title, created_at, URL
        table_header(sheet, %w[Title Users URL Categories])

        repositories.each do |repository|
          sheet.add_row [
                          repository.title,
                          repository.users.map(&:name).join(", "),
                          Rails.application.routes.url_helpers.repository_path(
                            id: repository.id,
                            user_username: repository.user_username
                          ),
                          repository.categories.map(&:name).join(", ")
                        ],
                        types: TEXT
        end
      end

    spreadsheet
  end

  # The type, location, date and instructor lines of a single session
  # workbook. A missing training, space or instructor shows Unknown.
  def self.session_summary_rows(session)
    [
      ["Training Type", session.training&.name_en || UNKNOWN],
      ["Location", session.space&.name || UNKNOWN_SPACE],
      ["Date", session.created_at.strftime("%Y-%m-%d %H:%M")],
      ["Instructor", session.user&.name || UNKNOWN]
    ]
  end
  private_class_method :session_summary_rows

  def self.generate_training_session_report(id)
    session =
      TrainingSession.includes(:user, :users, :space, :training).find(id)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Training Session")

        session_summary_rows(session).each do |row|
          sheet.add_row row, types: TEXT
        end
        sheet.add_row ["Course", session.course], types: TEXT
        sheet.add_row ["Number of Trainees", session.users.length]

        sheet.add_row # spacing

        table_header(sheet, %w[Name Email])

        session.users.each do |student|
          sheet.add_row [student.name, student.email], types: TEXT
        end
      end

    spreadsheet
  end

  def self.generate_space_present_users_report(id)
    now = Time.current
    lab_sessions =
      LabSession
        .includes(:user)
        .joins(:user)
        .where("space_id" => id)
        .where("sign_in_time < ?", now)
        .where("sign_out_time > ?", now)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Present Users")

        sheet.add_row ["Date", now.strftime("%Y-%m-%d %H:%M:%S")]

        sheet.add_row # spacing

        table_header(sheet, %w[Name Email])

        lab_sessions.each do |lab_session|
          sheet.add_row [lab_session.user.name, lab_session.user.email],
                        types: TEXT
        end
      end

    spreadsheet
  end

  def self.generate_peak_hours_report(start_date, end_date)
    ls = LabSession.arel_table
    # One row per day from the From date to the To date; the visits counted are
    # those of these whole days in the application time zone, so every hour
    # column comes from a visit on one of the rows.
    days = start_date.to_date..end_date.to_date

    result =
      ActiveRecord::Base.connection.exec_query(
        ls
          .project(
            ls["sign_in_time"].extract("YEAR").as("year"),
            ls["sign_in_time"].extract("MONTH").as("month"),
            ls["sign_in_time"].extract("DAY").as("day"),
            ls["sign_in_time"].extract("HOUR").as("hour"),
            Arel.star.count.as("total_visits")
          )
          .from(ls)
          .where(
            ls["sign_in_time"].between(
              days.begin.beginning_of_day..days.end.end_of_day
            )
          )
          .group("year", "month", "day", "hour")
          .to_sql
      )

    # The database stores UTC hours; each one is counted under its hour in the
    # application time zone, so the two UTC hours that fall in the repeated
    # hour when daylight saving time ends add up.
    visits_by_hour = Hash.new(0)
    result.each do |row|
      at =
        Time.utc(
          row["year"].to_i,
          row["month"].to_i,
          row["day"].to_i,
          row["hour"].to_i
        ).in_time_zone
      visits_by_hour[[at.to_date, at.hour]] += row["total_visits"].to_i
    end
    hours = visits_by_hour.keys.map(&:last)
    hour_columns = hours.empty? ? [] : (hours.min..hours.max).to_a

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet do |sheet|
      title(sheet, "Visitors by Hour")
      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      header = ["Date"]

      hour_columns.each { |hour| header << "%02i:00" % hour }

      table_header(sheet, header)

      days.each do |date|
        row = [date.strftime("%Y-%m-%d")]

        hour_columns.each { |hour| row << visits_by_hour[[date, hour]] }

        sheet.add_row row
      end
    end

    spreadsheet
  end

  def self.generate_kit_purchased_report(start_date, end_date)
    kits =
      ProjectKit
        .includes(:proficient_project, :user)
        .where("created_at" => start_date..end_date)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Purchased kits")

        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        table_header(sheet, ["Kit name", "User", "Date", "Delivery Status"])

        kits.each do |kit|
          status = kit.delivered? ? "Delivered" : "Not yet delivered"
          sheet.add_row [
                          kit.proficient_project.title,
                          kit.user.name,
                          kit.created_at,
                          status
                        ],
                        types: [TEXT, TEXT]
        end
      end

    spreadsheet
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

    # NOTE: I commented out the whole trainer stuff because that was disappearing some sessions
    # FIXME add trainer names
    query =
      TrainingSession
        .select(
          [
            t[:id].minimum.as("training_id"),
            t[:name].minimum.as("training_name"),
            ts[:level].minimum.as("training_level"),
            ts[:course].minimum.as("course_name"),
            uu[:name].minimum.as("instructor_name"),
            ts[:created_at].minimum.as("date"),
            s[:name].minimum.as("space_name"),
            u[:id].count.as("attendee_count")
          ]
        )
        .where(ts[:created_at].between(start_date..end_date))
        .joins(
          ts.join(t).on(t[:id].eq(ts[:training_id])).join_sources
        ) # training type
        # NOTE LEFT JOIN because some sessions aren't showing up otherwise
        # .joins(ts.join(tsu).on(ts[:id].eq(tsu[:training_session_id])).join_sources)
        .joins(
          "LEFT JOIN training_sessions_users ON training_sessions_users.training_session_id=training_sessions.id"
        )
        # .joins(ts.join(u).on(u[:id].eq(tsu[:user_id])).join_sources) # get users
        .joins("LEFT JOIN users ON users.id=training_sessions_users.user_id")
        .joins(
          ts.join(uu).on(uu[:id].eq(ts[:user_id])).join_sources
        ) # join trainers
        # .joins('LEFT JOIN users trainers on trainers.id=training_sessions.user_id')
        # .joins(ts.join(s).on(s[:id].eq(ts[:space_id])).join_sources)
        .joins(
          "LEFT JOIN spaces ON spaces.id=training_sessions.space_id"
        ) # some don't have space id?
        .group(ts[:id])
        .order(ts[:created_at].minimum)
        .to_sql

    ActiveRecord::Base.connection.exec_query(query)
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_certifications(start_date, end_date)
    c = Certification.arel_table
    ts = TrainingSession.arel_table
    t = Training.arel_table
    s = Space.arel_table

    # FIXME: please, if anyone else touches this again, replace it with active record functions instead
    # I'm not sure what this is called, I can't find any docs and uses Arel which is private API
    # except for https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html
    ActiveRecord::Base.connection.exec_query(
      Certification
        .select(
          [
            t["name"].minimum.as("name"), # training subject
            s["name"].minimum.as("space_name"), # space name
            ts["course"], # associated course
            c["training_session_id"].count(:distinct).as("total_sessions"), # number sessions
            Arel.star.count.as("total_certifications") #  active certs
          ]
        )
        .joins(
          c.join(ts).on(c["training_session_id"].eq(ts["id"])).join_sources
        )
        .joins(ts.join(t).on(ts["training_id"].eq(t["id"])).join_sources)
        # .joins(ts.join(s).on(ts["space_id"].eq(s["id"])).join_sources)
        # HACK you can't chain left_joins for some reason, https://github.com/rails/rails/issues/34332
        # so this is a manual left join string, because some training sessions don't have a space id attached?
        # and this causes some certs to be left out. Try Winter 2024 for an example.
        .joins("LEFT JOIN spaces on spaces.id=training_sessions.space_id")
        .where(ts["created_at"].between(start_date..end_date))
        .group(t["id"], s["id"], ts["course"])
        .order("name", "course", "space_name")
        .to_sql
    )
  end

  # endregion

  # region Axlsx helpers
  # @param [Axlsx::Worksheet] worksheet
  # @param [String] title
  def self.title(worksheet, title)
    worksheet.add_row [title, ""], b: true, u: :single
  end

  # @param [Axlsx::Worksheet] worksheet
  # @param [Array<String>] headers
  def self.table_header(worksheet, headers)
    header_row = worksheet.add_row headers, b: true
    worksheet.add_border header_row.cells.first.reference + ":" +
                           header_row.cells.last.reference,
                         { style: :thick, color: "00000000", edges: [:bottom] }
  end

  # @param [Axlsx::Worksheet] worksheet
  # @param [String] title
  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.header(worksheet, title, start_date, end_date)
    top_row = self.title(worksheet, title)
    worksheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
    bottom_row = worksheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
    worksheet.add_border top_row.cells.first.reference + ":" +
                           bottom_row.cells.last.reference
    worksheet.add_row # spacing
  end

  def self.push_hash(sheet, hash)
    hash.each { |key, value| sheet.add_row [key, value], types: LABEL_ROW }
  end

  # The calendar months or weeks (unit :month or :week) that overlap the
  # range, the partial ones at either end included, each as the range from
  # its first to its last instant, in the application time zone.
  def self.calendar_periods(start_date, end_date, unit)
    (start_date.in_time_zone.to_date..end_date.in_time_zone.to_date)
      .map { |day| day.public_send(:"beginning_of_#{unit}").in_time_zone }
      .uniq
      .map { |first| first..first.public_send(:"end_of_#{unit}") }
  end

  # Certificates per session among the certificates created in the period,
  # rounded to one decimal place (0.0 when there are none).
  def self.average_attendees_per_session(certifications, period)
    in_period =
      certifications.select { |cert| period.cover?(cert.created_at) }
    sessions = in_period.map(&:training_session_id).uniq.count
    sessions.zero? ? 0.0 : in_period.count.fdiv(sessions).round(1)
  end

  # Returns which engineering department a program belongs to
  def self.get_program_department(program)
    # HACK: Department list, this is hardcoded because we have no
    # structured way to describe them
    # Chemical/Bio, Civil, Mech, Elec, Innovation?
    case program
    when /Mechanical/
      "Mechanical"
    when /(Electrical|Computer|Software) Engineering/
      "EECS"
    when /Computer Science/
      "EECS"
    when /Civil/
      "Civil"
    when /Chemical|Biotechnology|Biomedical/
      "Chemical & Biological"
    else
      "Other Departments"
    end
    # /(Mechanical|Electrical|Chemical|Civil|Software|Computer) Engineering/
    #   .match(program)
    #   &.captures
    #   &.first or
    #   (program&.include? "Computer Science" and "Computer Science") or # Engineering category # CompSci Category
    #   "Non Engineering"
  end

  def self.get_study_level(program)
    if program =~ /BASc|(?<!M)BA|BSc|Bachel|BSocSc/
      "Bachelors"
    elsif program =~ /Mast/
      "Masters"
    elsif program =~ /PhD|Doctor/
      "Doctorate"
    else
      "None"
    end
  end

  # endregion
end
