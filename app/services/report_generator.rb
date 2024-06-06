# frozen_string_literal: true

# this is awful man.
# ReportGenerator here
# TODO: A whole lot of refactoring needed?
#   1. Separation of concerns. xslx template and data retrieval separated
#   2. Keep queries on controller side, you're sending network requests anyways to get the data
# axlsx doesn't read xlsx files, just writes them out. This sucks cuz I wanted to design a template and have it fill it in. Not sure if it's worth introducing a new gem.
# CSV won't work, this isn't the stone age and I want charts.
# I could move this all to controller side, but then it'll be difficult
# to use outside of that controller. This a massive file and smartparens is being stupid

class ReportGenerator
  require "axlsx"
  # region Date Range Reports

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_visitors_report(start_date, end_date)
    spreadsheet = Axlsx::Package.new

    # Query database for visitors
    # Our report gives
    space_details = get_visitors(start_date, end_date)

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        merge_cell = sheet.styles.add_style alignment: { vertical: :center }

        header(sheet, "Visitors", start_date, end_date)

        # region Overview
        title(sheet, "Overview")
        table_header(sheet, ["Space", "Distinct Users", "", "Total Visits"])

        space_details[:spaces].each do |space_name, space|
          sheet.add_row [space_name, space[:unique], "", space[:total]]
        end

        sheet.add_row # spacing

        table_header(sheet, ["Identity", "Distinct Users", "", "Total Visits"])

        space_details[:identities].each do |identity_name, space|
          sheet.add_row [identity_name, space[:unique], "", space[:total]]
        end

        sheet.add_row # spacing

        table_header(sheet, ["Faculty", "Distinct Users", "", "Total Visits"])

        space_details[:faculties].each do |faculty_name, space|
          sheet.add_row [faculty_name, space[:unique], "", space[:total]]
        end

        sheet.add_row # spacing

        table_header(
          sheet,
          ["Identity", "Distinct Users", "", "Total Visits", "", "Faculty"]
        )
        space_details[:identities].each do |identity_name, identity|
          start_index = sheet.rows.last.row_index + 1

          identity[:faculties].each do |faculty_name, faculty|
            sheet.add_row [
                            identity_name,
                            faculty[:unique],
                            "",
                            faculty[:total],
                            "",
                            faculty_name
                          ],
                          style: [merge_cell]
          end

          end_index = sheet.rows.last.row_index

          sheet.merge_cells("A#{start_index + 1}:A#{end_index + 1}")
        end

        sheet.add_row # spacing
        # endregion
      end

    # region Per-space details
    space_details[:spaces].each do |space_name, space_detail|
      spreadsheet
        .workbook
        .add_worksheet(name: space_name) do |sheet|
          title(sheet, space_name)

          faculty_hash = {}
          merge_cell = sheet.styles.add_style alignment: { vertical: :center }

          table_header(
            sheet,
            ["Identity", "Distinct Users", "", "Total Visits"]
          )
          space_detail[:identities].each do |identity_name, identity|
            sheet.add_row [
                            identity_name,
                            identity[:unique],
                            "",
                            identity[:total]
                          ]
          end

          sheet.add_row # spacing

          table_header(sheet, ["Faculty", "Distinct Users", "", "Total Visits"])
          space_detail[:faculties].each do |faculty_name, faculty|
            sheet.add_row [faculty_name, faculty[:unique], "", faculty[:total]]
          end

          sheet.add_row # spacing

          table_header(
            sheet,
            ["Identity", "Distinct Users", "", "Total Visits", "", "Faculty"]
          )
          space_detail[:identities].each do |identity_name, identity|
            start_index = sheet.rows.last.row_index + 1

            identity[:faculties].each do |faculty_name, faculty|
              sheet.add_row [
                              identity_name,
                              faculty[:unique],
                              "",
                              faculty[:total],
                              "",
                              faculty_name
                            ],
                            style: [merge_cell]
              if faculty_hash[faculty_name].blank?
                faculty_hash[faculty_name] = faculty[:unique]
              else
                faculty_hash[faculty_name] = faculty[:unique] +
                  faculty_hash[faculty_name]
              end
            end

            end_index = sheet.rows.last.row_index

            sheet.merge_cells("A#{start_index + 1}:A#{end_index + 1}")
          end

          sheet.add_row # spacing

          table_header(sheet, ["Gender", "Distinct Users", "", "Total Visits"])
          space_detail[:genders].each do |gender_name, gender|
            sheet.add_row [gender_name, gender[:unique], "", gender[:total]]
          end

          space = sheet.add_row # spacing

          male =
            (
              if space_detail[:genders]["Male"].present?
                space_detail[:genders]["Male"][:unique]
              else
                0
              end
            )
          female =
            (
              if space_detail[:genders]["Female"].present?
                space_detail[:genders]["Female"][:unique]
              else
                0
              end
            )
          other =
            (
              if space_detail[:genders]["Other"].present?
                space_detail[:genders]["Other"][:unique]
              else
                0
              end
            )
          prefer_not =
            (
              if space_detail[:genders]["Prefer not to specify"].present?
                space_detail[:genders]["Prefer not to specify"][:unique]
              else
                0
              end
            )
          final_other = other + prefer_not

          sheet.add_chart(
            Axlsx::Pie3DChart,
            rot_x: 90,
            start_at: "A#{space.row_index + 2}",
            end_at: "E#{space.row_index + 14}",
            grouping: :stacked,
            show_legend: true,
            title: "Gender of unique users"
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

          sheet.add_chart(
            Axlsx::Pie3DChart,
            rot_x: 90,
            start_at: "A#{space.row_index + 16}",
            end_at: "E#{space.row_index + 28}",
            grouping: :stacked,
            show_legend: true,
            title: "Faculty of unique users"
          ) do |chart2|
            chart2.add_series data: faculty_hash.values,
                              labels: faculty_hash.keys,
                              colors: %w[
                                416145
                                33EEDD
                                860F48
                                88E615
                                6346F0
                                F5E1FE
                                E9A55B
                                A2F8FA
                                260AD2
                                12032E
                                755025
                                723634
                              ]
            chart2.add_series data: faculty_hash.values,
                              labels: faculty_hash.keys,
                              colors: %w[
                                416145
                                33EEDD
                                860F48
                                88E615
                                6346F0
                                F5E1FE
                                E9A55B
                                A2F8FA
                                260AD2
                                12032E
                                755025
                                723634
                              ]
            chart2.d_lbls.show_percent = true
            chart2.d_lbls.d_lbl_pos = :bestFit
          end
        end
    end
    # endregion

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_trainings_report(start_date, end_date)
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

        trainings[:training_types].each do |_, training_type|
          sheet.add_row [
                          training_type[:name],
                          training_type[:count],
                          training_type[:total_attendees]
                        ]
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

        trainings[:training_sessions].each do |row|
          training = Training.find(row[:training_id])
          color =
            if training.skill_id.present?
              if training.skill.name == "Machine Shop Training"
                { bg_color: "ed7d31" }
              elsif training.skill.name == "Technology Trainings"
                { bg_color: "70ad47" }
              elsif training.skill.name == "CEED Trainings"
                { bg_color: "ffc000" }
              else
                {}
              end
            else
              {}
            end
          style = sheet.styles.add_style(color)

          sheet.add_row [
                          row[:training_name],
                          row[:training_level],
                          row[:course_name],
                          row[:instructor_name],
                          row[:date].localtime.strftime("%Y-%m-%d %H:%M"),
                          row[:facility],
                          row[:attendee_count]
                        ],
                        style: [style]
        end
      end

    spreadsheet
  end

  # FIXME: there is a separate fetch function, use it???
  # Fetch certifications, per space
  # FUN FACT: This thing never touches the 'certifications' table, for some unfathomable reason.
  # tldr this is broken and doesn't actually count handed out certs, rewrite completely.
  # I'm assuming there's some double counted certs here :/
  # FIXME no infinte date range
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
    #heading_style = spreadsheet.workbook.styles.add_style
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
    spaces = spaces.uniq.sort { |a, b| a && b ? a <=> b : a ? 1 : -1 }.reverse
    topics = topics.uniq
    courses = courses.uniq #.map { |d| d || "None" }

    (spaces + ["total"]).each do |space|
      spreadsheet
        .workbook
        .add_worksheet(name: space || "Unknown") do |sheet|
          title(sheet, "Makerepo Certifications report")
          title_string = "Certifications granted in #{space}"
          header(sheet, title_string, start_date, end_date)
          sheet.column_widths title_string.length + 2

          # push headers, add space to be merged
          sheet.add_row [""] + courses.map { |d| [d || "Open", ""] }.flatten +
                          ["Total", ""],
                        style: centered_style
          # merge subheaders
          (courses.count + 2).times do |n|
            n = n * 2 + 1
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

              #|| [0, 0] # default if not found
              entry += this_space == [] ? [0, 0] : this_space
            end

            # sum sessions
            total_sessions = entry.drop(1).each_slice(2).map(&:first).sum
            total_certs = entry.drop(1).each_slice(2).map(&:last).sum
            entry += [total_sessions, total_certs]

            # finally push row
            sheet.add_row entry, style: centered_style
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

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_new_users_report(start_date, end_date)
    users = User.between_dates_picked(start_date, end_date)

    spreadsheet = Axlsx::Package.new

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

        groups = users.group_by(&:identity)

        groups.each do |group_name, values|
          sheet.add_row [group_name, values.length]
        end

        sheet.add_row # spacing

        table_header(
          sheet,
          [
            "Name",
            "Username",
            "Email",
            "Gender",
            "Identity",
            "Faculty",
            "Year of Study",
            "Student ID",
            "Joined on"
          ]
        )

        users.each do |user|
          sheet.add_row [
                          user.name,
                          user.username,
                          user.email,
                          user.gender,
                          user.identity,
                          user.faculty,
                          user.year_of_study,
                          user.created_at.localtime.strftime("%Y-%m-%d %H:%M")
                        ]
        end
      end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_training_attendees_report(start_date, end_date)
    certifications =
      Certification
        .includes({ training_session: %i[user training space] }, :user)
        .where("created_at" => start_date..end_date)
        .order(
          "spaces.name",
          "training_sessions.created_at",
          "users_certifications.name"
        )
        .group_by { |item| item.training_session.space.id }

    spreadsheet = Axlsx::Package.new

    certifications.each do |_space, space_certifications|
      spreadsheet
        .workbook
        .add_worksheet(
          name:
            "Report - #{space_certifications[0].training_session.space.name}"
        ) do |sheet|
          merge_cell = sheet.styles.add_style alignment: { vertical: :center }

          title(
            sheet,
            "Training Attendees - #{space_certifications[0].training_session.space.name}"
          )

          sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
          sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
          sheet.add_row # spacing

          table_header(
            sheet,
            [
              "Student ID",
              "Name",
              "Email Address",
              "Certification Type",
              "Certification Date",
              "Instructor",
              "Course",
              "Facility"
            ]
          )

          start_index = sheet.rows.last.row_index + 2
          last_training_session_id = nil

          space_certifications.each do |certification|
            if (
                 last_training_session_id != certification.training_session.id
               ) && !last_training_session_id.nil?
              end_index = sheet.rows.last.row_index + 1

              if start_index < end_index
                sheet.merge_cells("A#{start_index}:A#{end_index}")
                sheet.merge_cells("B#{start_index}:B#{end_index}")
                sheet.merge_cells("C#{start_index}:C#{end_index}")
                sheet.merge_cells("D#{start_index}:D#{end_index}")
                sheet.merge_cells("E#{start_index}:E#{end_index}")
                sheet.merge_cells("F#{start_index}:F#{end_index}")
                sheet.merge_cells("G#{start_index}:G#{end_index}")
                sheet.merge_cells("H#{start_index}:H#{end_index}")
              end

              start_index = sheet.rows.last.row_index + 2
            end

            sheet.add_row [
                            certification.user.name,
                            certification.user.email,
                            certification.training_session.training.name,
                            certification.training_session.created_at.strftime(
                              "%Y-%m-%d %H:%M"
                            ),
                            certification.training_session.user.name,
                            certification.training_session.course,
                            certification.training_session.space.name
                          ],
                          style: [
                            merge_cell,
                            merge_cell,
                            merge_cell,
                            merge_cell,
                            merge_cell
                          ]

            last_training_session_id = certification.training_session.id
          end

          sheet.add_row #spacing

          month_average = ["Month average of attendees per sessions"]
          month_header = ["Month"]

          (start_date.to_datetime..end_date.to_datetime)
            .select { |date| date.day == 1 }
            .map do |date|
              month_header << date.strftime("%B")
              month_certifications =
                space_certifications.select do |cert|
                  cert.created_at.between?(
                    date.beginning_of_month,
                    date.end_of_month
                  )
                end
              average =
                if month_certifications.count.zero? ||
                     month_certifications
                       .pluck(:training_session_id)
                       .uniq
                       .count
                       .zero?
                  0
                else
                  month_certifications.count /
                    month_certifications.pluck(:training_session_id).uniq.count
                end
              month_average << average
            end

          table_header(sheet, month_header)
          sheet.add_row month_average
          sheet.add_row #spacing

          week_average = ["Week average of attendees per sessions"]
          week_header = ["Week"]

          (start_date.to_datetime.to_i..end_date.to_datetime.to_i).step(
            1.week
          ) do |date|
            week_header << "#{Time.at(date).beginning_of_week.strftime("%Y-%m-%d")} to #{Time.at(date).end_of_week.strftime("%Y-%m-%d")}"
            week_certifications =
              space_certifications.select do |cert|
                cert.created_at.between?(
                  Time.at(date).beginning_of_week,
                  Time.at(date).end_of_week
                )
              end
            average =
              if week_certifications.count.zero? ||
                   week_certifications
                     .pluck(:training_session_id)
                     .uniq
                     .count
                     .zero?
                0
              else
                week_certifications.count /
                  week_certifications.pluck(:training_session_id).uniq.count
              end
            week_average << average
          end

          table_header(sheet, week_header)
          sheet.add_row week_average
          sheet.add_row #spacing
        end
    end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_new_projects_report(start_date, end_date)
    #aggregate_data = get_new_projects(start_date, end_date)

    repositories =
      Repository.where("created_at" => start_date..end_date).includes(
        :users,
        :categories,
        :equipments
      )

    spreadsheet = Axlsx::Package.new
    #raise "repl pls"

    # Category|Count
    # --------|-----
    # cat 1   |10
    # cat 2   |20

    # group by category, first find all categories
    # FIXME schema is messed up, yes there's a separate category for each repo
    category_count = Category.group(:name).count

    spreadsheet
      .workbook
      .add_worksheet(name: "Statistics") do |sheet|
        title(sheet, "Various statistics")
        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        title(sheet, "Categories")
        category_count.each { |key, value| sheet.add_row [key, value] }

        sheet.add_row

        title(sheet, "Equipment usage")
        equipment =
          Equipment.where(created_at: start_date..end_date).group(:name).count
        equipment.each { |key, value| sheet.add_row [key, value] }

        sheet.add_row

        title(sheet, "Licenses")
        repositories
          .group(:license)
          .count
          .each { |key, value| sheet.add_row [key, value] }

        sheet.add_row
        title(sheet, "Share types")

        repositories
          .group(:share_type)
          .count
          .each { |key, value| sheet.add_row [key, value] }
      end

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "New Projects")

        sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
        sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
        sheet.add_row # spacing

        # FIXME this sucks, fix it
        # Title, created_at, URL
        table_header(sheet, %w[Title Users URL Categories])

        # who the fuck wrote this?
        repositories.each do |repository|
          sheet.add_row [
                          repository.title,
                          repository.users.map(&:name).join(", "),
                          Rails.application.routes.url_helpers.repository_path(
                            id: repository.id,
                            user_username: repository.user_username
                          ),
                          repository.categories.map(&:name).join(", ")
                        ]
        end
      end

    spreadsheet
  end

  # @param [Integer] id
  def self.generate_training_session_report(id)
    session =
      TrainingSession.includes(:user, :users, :space, :training).find(id)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Training Session")

        sheet.add_row ["Training Type", session.training.name]
        sheet.add_row ["Location", session.space.name]
        sheet.add_row ["Date", session.created_at.strftime("%Y-%m-%d %H:%M")]
        sheet.add_row ["Instructor", session.user.name]
        sheet.add_row ["Course", session.course]
        sheet.add_row ["Number of Trainees", session.users.length]

        sheet.add_row # spacing

        table_header(sheet, %w[Name Email])

        session.users.each do |student|
          sheet.add_row [student.name, student.email]
        end
      end

    spreadsheet
  end

  # @param [Integer] id
  def self.generate_space_present_users_report(id)
    lab_sessions =
      LabSession
        .includes(:user)
        .joins(:user)
        .where("space_id" => id)
        .where("sign_in_time < ?", DateTime.now)
        .where("sign_out_time > ?", DateTime.now)

    spreadsheet = Axlsx::Package.new

    spreadsheet
      .workbook
      .add_worksheet(name: "Report") do |sheet|
        title(sheet, "Present Users")

        sheet.add_row ["Date", DateTime.now.strftime("%Y-%m-%d %H:%M:%S")]

        sheet.add_row # spacing

        table_header(sheet, %w[Name Email])

        lab_sessions.each do |lab_session|
          sheet.add_row [lab_session.user.name, lab_session.user.email]
        end
      end

    spreadsheet
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_peak_hours_report(start_date, end_date)
    ls = LabSession.arel_table

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
          .where(ls["sign_in_time"].between(start_date..end_date))
          .group("year", "month", "day", "hour")
          .to_sql
      )

    visits_by_hour = {}
    min_hour = 23
    max_hour = 0

    result.each do |row|
      year = row["year"].to_i
      month = row["month"].to_i
      day = row["day"].to_i
      hour = row["hour"].to_i
      total_visits = row["total_visits"].to_i

      date = DateTime.new(year, month, day, hour).localtime

      min_hour = [min_hour, date.hour].min
      max_hour = [max_hour, date.hour].max

      visits_by_hour[date.year] = {} unless visits_by_hour[date.year]

      visits_by_hour[date.year][date.month] = {} unless visits_by_hour[
        date.year
      ][
        date.month
      ]

      visits_by_hour[date.year][date.month][date.day] = {
      } unless visits_by_hour[date.year][date.month][date.day]

      visits_by_hour[date.year][date.month][date.day][date.hour] = total_visits
    end

    spreadsheet = Axlsx::Package.new

    spreadsheet.workbook.add_worksheet do |sheet|
      title(sheet, "Visitors by Hour")
      sheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
      sheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
      sheet.add_row # spacing

      header = ["Date"]

      (min_hour..max_hour).each { |hour| header << "%02i:00" % hour }

      table_header(sheet, header)

      (start_date..end_date).each do |date|
        row = [date.strftime("%Y-%m-%d")]

        (min_hour..max_hour).each do |hour|
          if visits_by_hour[date.year] &&
               visits_by_hour[date.year][date.month] &&
               visits_by_hour[date.year][date.month][date.day] &&
               visits_by_hour[date.year][date.month][date.day][hour]
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

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.generate_kit_purchased_report(start_date, end_date)
    kits = ProjectKit.where("created_at" => start_date..end_date)

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
                        ]
        end
      end

    spreadsheet
  end

  # endregion

  # region Database helpers

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_new_projects(start_date, end_date)
    # Essentially a copy of html report as xlsx
    # Breakdown of projects by month
    # By category, license, project type,
    repos = Repository.arel_table
    categories = Category.arel_table
    propos = ProjectProposal.arel_table
    equips = Equipment.arel_table

    # Repository.select("date_trunc('year', created_at) as year, date_trunc('month', created_at) as month")
    #           .includes(:categories)
    #           .includes(:equipments)
    #           .where(created_at: start_date..end_date)
    #           .group("month")
    ActiveRecord::Base.connection.exec_query(
      Repository
        .select(
          [
            #repos["created_at"].as("created"),
            repos["id"],
            "to_char(repositories.created_at, 'MM') as created_month", # NOTE postgresql specific hack to get month, year
            "to_char(repositories.created_at, 'YYYY') as created_year",
            repos["license"],
            #repos["license"].count().as("license_count"),
            repos["share_type"],
            categories["name"],
            equips["name"]
            #Arel.star.count
          ]
        )
        .joins(
          repos
            .join(categories)
            .on(repos["id"].eq(categories["repository_id"]))
            .join_sources
        )
        .joins(
          repos
            .join(equips)
            .on(repos["id"].eq(equips["repository_id"]))
            .join_sources
        )
        .where(repos["created_at"].between(start_date..end_date))
        .to_sql
      #.group(repos["share_type"], repos["license"], categories["name"],
      #       equips["name"], "created_month", "created_year")
    )
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_visitors(start_date, end_date)
    g = Arel::Table.new("g")
    ls = LabSession.arel_table
    u = User.arel_table
    s = Space.arel_table

    # NOTE: notice how this dance isn't necessary, you can just hit the activerecord
    # you want without passing by exec_query
    result =
      ActiveRecord::Base.connection.exec_query(
        g
          .project(
            [
              g[:space_name].minimum.as("space_name"),
              g[:identity],
              g[:faculty],
              g[:gender],
              Arel.star.count.as("unique_visitors"),
              g[:count].sum.as("total_visits")
            ]
          )
          .from(
            LabSession
              .select(
                [
                  ls[:space_id],
                  s[:name].minimum.as("space_name"),
                  u[:identity],
                  u[:faculty],
                  u[:gender],
                  Arel.star.count
                ]
              )
              .joins(ls.join(u).on(u[:id].eq(ls[:user_id])).join_sources)
              .joins(ls.join(s).on(s[:id].eq(ls[:space_id])).join_sources)
              .where(ls[:sign_in_time].between(start_date..end_date))
              .group(
                ls[:space_id],
                ls[:user_id],
                u[:faculty],
                u[:identity],
                u[:gender]
              )
              .arel
              .as(g.name)
          )
          .order(g[:space_name].minimum, g[:identity], g[:faculty], g[:gender])
          .group(g[:space_id], g[:identity], g[:faculty], g[:gender])
          .to_sql
      )

    # shove everything into a hash
    organized = {
      unique: 0,
      total: 0,
      spaces: {
      },
      identities: {
      },
      faculties: {
      },
      genders: {
      }
    }

    result.each do |row|
      space_name = row["space_name"]
      faculty = row["faculty"].presence || "Unknown"
      gender = row["gender"]

      identity =
        case row["identity"]
        when "undergrad"
          "Undergraduate"
        when "grad"
          "Graduate"
        when "faculty_member"
          "Faculty Member"
        when "community_member"
          "Community Member"
        else
          "Unknown"
        end

      unless organized[:spaces][space_name]
        organized[:spaces][space_name] = {
          unique: 0,
          total: 0,
          identities: {
          },
          faculties: {
          },
          genders: {
          }
        }
      end

      unless organized[:spaces][space_name][:identities][identity]
        organized[:spaces][space_name][:identities][identity] = {
          unique: 0,
          total: 0,
          faculties: {
          }
        }
      end

      unless organized[:spaces][space_name][:identities][identity][:faculties][
               faculty
             ]
        organized[:spaces][space_name][:identities][identity][:faculties][
          faculty
        ] = { unique: 0, total: 0 }
      end

      unless organized[:spaces][space_name][:faculties][faculty]
        organized[:spaces][space_name][:faculties][faculty] = {
          unique: 0,
          total: 0
        }
      end

      unless organized[:spaces][space_name][:genders][gender]
        organized[:spaces][space_name][:genders][gender] = {
          unique: 0,
          total: 0
        }
      end

      organized[:identities][identity] = {
        unique: 0,
        total: 0,
        faculties: {
        }
      } unless organized[:identities][identity]

      unless organized[:identities][identity][:faculties][faculty]
        organized[:identities][identity][:faculties][faculty] = {
          unique: 0,
          total: 0
        }
      end

      organized[:faculties][faculty] = { unique: 0, total: 0 } unless organized[
        :faculties
      ][
        faculty
      ]

      organized[:genders][gender] = { unique: 0, total: 0 } unless organized[
        :genders
      ][
        gender
      ]

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

      organized[:spaces][space_name][:identities][identity][:faculties][
        faculty
      ][
        :unique
      ] += unique
      organized[:spaces][space_name][:identities][identity][:faculties][
        faculty
      ][
        :total
      ] += total

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
            Arel.star.count.as("attendee_count")
          ]
        )
        .where(ts[:created_at].between(start_date..end_date))
        .joins(ts.join(t).on(t[:id].eq(ts[:training_id])).join_sources)
        .joins(
          ts.join(tsu).on(ts[:id].eq(tsu[:training_session_id])).join_sources
        )
        .joins(ts.join(u).on(u[:id].eq(tsu[:user_id])).join_sources)
        .joins(ts.join(uu).on(uu[:id].eq(ts[:user_id])).join_sources)
        .joins(ts.join(s).on(s[:id].eq(ts[:space_id])).join_sources)
        .group(ts[:id])
        .order(ts[:created_at].minimum)
        .to_sql

    result = { training_sessions: [], training_types: {} }

    ActiveRecord::Base
      .connection
      .exec_query(query)
      .each do |row|
        result[:training_sessions] << {
          training_id: row["training_id"],
          training_name: row["training_name"],
          training_level: row["training_level"],
          course_name: row["course_name"],
          instructor_name: row["instructor_name"],
          date: DateTime.strptime(row["date"].to_s, "%Y-%m-%d %H:%M:%S"),
          facility: row["space_name"],
          attendee_count: row["attendee_count"].to_i
        }

        unless result[:training_types][row["training_id"]]
          result[:training_types][row["training_id"]] = {
            name: row["training_name"],
            count: 0,
            total_attendees: 0
          }
        end

        result[:training_types][row["training_id"]][:count] += 1
        result[:training_types][row["training_id"]][:total_attendees] += row[
          "attendee_count"
        ].to_i
      end

    result
  end

  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.get_certifications(start_date, end_date)
    c = Certification.arel_table
    ts = TrainingSession.arel_table
    t = Training.arel_table
    s = Space.arel_table

    # FIXME please, if anyone else touches this again, replace it with active record functions instead
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
        #.joins(ts.join(s).on(ts["space_id"].eq(s["id"])).join_sources)
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
  # FIXME: make this nicer, add more styling
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

  # @param [Axlsx::Worksheet] worksheet
  # @param [String] title
  # @param [DateTime] start_date
  # @param [DateTime] end_date
  def self.header(worksheet, title, start_date, end_date)
    self.title(worksheet, title)
    worksheet.add_row ["From", start_date.strftime("%Y-%m-%d")]
    worksheet.add_row ["To", end_date.strftime("%Y-%m-%d")]
    worksheet.add_row # spacing
  end

  # endregion
end
