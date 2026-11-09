# frozen_string_literal: true

require "rails_helper"

# Characterization of the workbook contents ReportGenerator builds, beyond the
# representative checks in report_generator_spec.rb: every sheet, row and header
# for populated data, the edge ranges, and the helper methods that no
# controller action calls any more.
RSpec.describe ReportGenerator do
  include Chunk18Helpers
  include ActiveSupport::Testing::TimeHelpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:from) { DateTime.new(2026, 3, 1) }
  let(:to) { DateTime.new(2026, 3, 31) }

  # { sheet name => rows }, each row without its trailing empty cells.
  def grid(package)
    c18_xlsx_sheets(package.to_stream.read).transform_values do |rows|
      rows.map { |row| row.dup.tap { |r| r.pop while !r.empty? && r.last.nil? } }
    end
  end

  # Splits a sheet at its blank spacer rows.
  def blocks(rows)
    rows.slice_when { |a, _| a.empty? }.map { |b| b.reject(&:empty?) }
  end

  # Runs the example with the server's local zone set away from the
  # application zone (Toronto), so a time printed in the server's zone shows.
  def self.on_a_server_in_another_zone
    around do |example|
      server_zone = ENV.fetch("TZ", nil)
      ENV["TZ"] = "Asia/Tokyo"
      example.run
    ensure
      ENV["TZ"] = server_zone
    end
  end

  def student(name, **attrs)
    create(:user, :student, name: name, created_at: march_10, **attrs)
  end

  describe ".generate_visitors_report" do
    let!(:alpha) { create(:space, name: "Alpha") }
    let!(:beta) { create(:space, name: "Beta") }

    before do
      gina = student("Gina Genie", gender: "Female")
      gina.update_columns(faculty: "Génie")
      cam = create(:user, name: "Cam Community", created_at: march_10, gender: "Male")
      cam.update_columns(faculty: "", program: nil)
      mo = student("Mo Master", program: "Master of Arts", faculty: "Arts", gender: "Male")
      phil = student("Phil Doc", faculty: "Science", gender: "Other")
      phil.update_columns(program: "  ﻿PhD Physics")
      [[alpha, gina], [alpha, gina], [alpha, cam], [beta, mo], [beta, phil]].each do |space, user|
        create(:lab_session, space: space, user: user, created_at: march_10)
      end
      create(:lab_session, space: alpha, user: gina, created_at: Time.utc(2026, 4, 2))
    end

    let(:sheets) { grid(described_class.generate_visitors_report(from, to)) }

    it "has the overview, one sheet per visited space and a Programs sheet" do
      expect(sheets.keys).to match_array(%w[Report Alpha Beta Programs])
      expect(sheets["Report"].first(8)).to eq(
        [["Visitors"], ["From", "2026-03-01"], ["To", "2026-03-31"], [], ["Overview"],
         ["CEED-Wide unique visitors", 4], ["CEED-Wide total visitors", 5], []]
      )
    end

    it "overview: identity, gender, faculty, identity-by-faculty and department tables" do
      b = blocks(sheets["Report"])
      identity, gender, faculty, identity_faculty, department = b[2..6]
      expect(identity.first).to eq(["Identity", "Distinct Users", nil, "Total Visits"])
      expect(identity.drop(1)).to contain_exactly(["Community member", 1, nil, 1], ["Undergrad", 3, nil, 4])
      expect(gender).to eq([%w[Gender Count], ["Female", 1], ["Male", 2], ["Other", 1]])
      expect(faculty.first).to eq(["Faculty", "Distinct Users", nil, "Total Visits"])
      # Génie is merged into Engineering and the blank faculty shows as None
      expect(faculty.drop(1)).to contain_exactly(
        ["None", 1, nil, 1], ["Engineering", 1, nil, 2], ["Science", 1, nil, 1], ["Arts", 1, nil, 1]
      )
      expect(identity_faculty.first).to eq(["Identity", "Distinct Users", nil, "Total Visits", nil, "Faculty"])
      expect(identity_faculty.drop(1)).to contain_exactly(
        ["Community member", 1, nil, 1, nil, "None"], ["Undergrad", 1, nil, 2, nil, "Engineering"],
        ["Undergrad", 1, nil, 1, nil, "Science"], ["Undergrad", 1, nil, 1, nil, "Arts"]
      )
      expect(department.first).to eq(["Department", "Distinct Users", nil, "Total Visits", nil, "Level"])
      expect(department.drop(1)).to contain_exactly(
        ["Other Departments", 1, nil, 1, nil, "Doctorate"], ["Other Departments", 1, nil, 1, nil, "Masters"],
        ["Other Departments", 1, nil, 1, nil, "None"], ["EECS", 1, nil, 2, nil, "Bachelors"]
      )
    end

    it "merges a French faculty into its English name and shows a missing faculty as None" do
      gamma = create(:space, name: "Gamma")
      %w[Éducation Education].each do |name|
        user = student("Ed #{name}")
        user.update_columns(faculty: name)
        create(:lab_session, space: gamma, user: user, created_at: march_10)
      end
      nobody = student("No Faculty")
      nobody.update_columns(faculty: nil)
      create(:lab_session, space: gamma, user: nobody, created_at: march_10)
      b = blocks(grid(described_class.generate_visitors_report(from, to))["Gamma"])
      expect(b[4].drop(1)).to contain_exactly(["Education", 2, nil, 2], ["None", 1, nil, 1])
      expect(b[5].drop(1).map(&:last)).to contain_exactly("Education", "None")
    end

    it "shows visitors with a missing or blank identity in one None row" do
      gamma = create(:space, name: "Gamma")
      { "Nil Identity" => nil, "Blank Identity" => "" }.each do |name, identity|
        user = student(name)
        user.update_columns(identity: identity)
        create(:lab_session, space: gamma, user: user, created_at: march_10)
      end
      b = blocks(grid(described_class.generate_visitors_report(from, to))["Gamma"])
      expect(b[2].drop(1)).to eq([["None", 2, nil, 2]])
      expect(b[5].drop(1).map(&:first)).to eq(["None"])
    end

    it "a space sheet repeats the tables for that space only" do
      b = blocks(sheets["Beta"])
      expect(b[1]).to eq([["Report for Beta"]])
      expect(b[2].drop(1)).to contain_exactly(["Undergrad", 2, nil, 2])
      expect(b[3]).to eq([%w[Gender Count], ["Male", 1], ["Other", 1]])
      expect(b[4].drop(1)).to contain_exactly(["Science", 1, nil, 1], ["Arts", 1, nil, 1])
      expect(b[6].drop(1)).to contain_exactly(
        ["Other Departments", 1, nil, 1, nil, "Doctorate"], ["Other Departments", 1, nil, 1, nil, "Masters"]
      )
    end

    it "Programs sheet strips leading non-word characters and files blank programs under None" do
      expect(sheets["Programs"]).to eq(
        [["program", "Distinct Users", nil, "Total Visits"],
         ["BASc in Software Engineering", 1, nil, 2], ["Master of Arts", 1, nil, 1],
         ["None", 1, nil, 1], ["PhD Physics", 1, nil, 1]]
      )
    end

    it "counts a visit created on the last instant of the end date but not the next day" do
      create(:lab_session, space: beta, user: create(:user, :student), created_at: Time.utc(2026, 3, 31, 23, 59, 59))
      rows = grid(described_class.generate_visitors_report(from, DateTime.new(2026, 3, 31).end_of_day))["Report"]
      expect(rows).to include(["CEED-Wide total visitors", 6])
      midnight = grid(described_class.generate_visitors_report(from, to))["Report"]
      expect(midnight).to include(["CEED-Wide total visitors", 5])
    end
  end

  describe ".generate_trainings_report" do
    let!(:alpha) { create(:space, name: "Alpha") }
    let(:laser) { create(:training, name_en: "Laser", name: "Laser") }
    let(:saw) { create(:training, name_en: "Saw", name: "Saw") }

    on_a_server_in_another_zone

    it "summarises per training, then lists every session with its instructor, Toronto time and attendee count" do
      teacher = create(:user, :staff, name: "Ina Instructor")
      busy = create(:training_session, space: alpha, training: laser, user: teacher, course: "MCG1", created_at: march_10)
      busy.users << create(:user, name: "A One") << create(:user, name: "B Two")
      create(:training_session, space: alpha, training: saw, user: teacher, created_at: march_10 + 1.day)
                                 .users << create(:user, name: "C Three")
      rows = grid(described_class.generate_trainings_report(from, to))["Report"]
      expect(rows.first(5)).to eq(
        [["Trainings"], ["From", "2026-03-01"], ["To", "2026-03-31"], [],
         ["Training", "Session Count", "Total Attendees"]]
      )
      expect(rows[5..6]).to contain_exactly(["Laser", 1, 2], ["Saw", 1, 1])
      expect(rows[7]).to eq([])
      expect(rows[8]).to eq(%w[Training Level Course Instructor Date Facility] + ["Attendee Count"])
      expect(rows[9..]).to contain_exactly(
        ["Laser", "Beginner", "MCG1", "Ina Instructor", "2026-03-10 11:00", "Alpha", 2],
        ["Saw", "Beginner", nil, "Ina Instructor", "2026-03-11 11:00", "Alpha", 1]
      )
    end

    it "counts no attendees for a session nobody attended" do
      create(:training_session, space: alpha, training: laser, created_at: march_10)
      create(:training_session, space: alpha, training: laser, created_at: march_10 + 1.hour)
        .users << create(:user)
      rows = grid(described_class.generate_trainings_report(from, to))["Report"]
      expect(rows[5]).to eq(["Laser", 2, 1])
      expect(rows[8..].map(&:last)).to contain_exactly(0, 1)
    end

    it "leaves the facility blank for a session without a space" do
      session = create(:training_session, space: alpha, training: saw, created_at: march_10)
      session.update_columns(space_id: nil)
      rows = grid(described_class.generate_trainings_report(from, to))["Report"]
      expect(rows.last[5]).to be_nil
    end

    it "with nothing in the range has only the two header rows" do
      rows = grid(described_class.generate_trainings_report(from, to))["Report"]
      expect(rows).to eq(
        [["Trainings"], ["From", "2026-03-01"], ["To", "2026-03-31"], [],
         ["Training", "Session Count", "Total Attendees"], [],
         ["Training", "Level", "Course", "Instructor", "Date", "Facility", "Attendee Count"]]
      )
    end
  end

  describe ".generate_certifications_report" do
    let!(:alpha) { create(:space, name: "Alpha") }
    let(:laser) { create(:training, name: "Laser") }
    let(:saw) { create(:training, name: "Saw") }

    def cert(session, user_name)
      create(:certification, user: create(:user, name: user_name), training_session: session, training: session.training,
                             created_at: session.created_at)
    end

    before do
      course = create(:training_session, space: alpha, training: laser, course: "MCG1", created_at: march_10)
      open_laser = create(:training_session, space: alpha, training: laser, created_at: march_10 + 1.day)
      no_space = create(:training_session, space: alpha, training: saw, created_at: march_10 + 2.days)
      no_space.update_columns(space_id: nil)
      cert(course, "P1")
      cert(course, "P2")
      cert(open_laser, "P3")
      cert(no_space, "P4")
    end

    let(:sheets) { grid(described_class.generate_certifications_report(from, to)) }

    it "makes a sheet per space (the sessions without one under Unknown) and a total sheet" do
      expect(sheets.keys).to eq(%w[Alpha Unknown total])
    end

    it "per space: course columns (blank course is Open), sessions and certificates per training, a totals row" do
      expect(sheets["Alpha"]).to eq(
        [["Makerepo Certifications report"], ["Certifications granted in Alpha"], ["From", "2026-03-01"],
         ["To", "2026-03-31"], [],
         [nil, "MCG1", nil, "Open", nil, "Total"],
         ["Training", "Completed sessions", "Certs awarded", "Completed sessions", "Certs awarded",
          "Completed sessions", "Certs awarded"],
         ["Laser", 1, 2, 1, 1, 2, 3], ["Saw", 0, 0, 0, 0, 0, 0],
         ["Total", 1, 2, 1, 1, 2, 3]]
      )
    end

    it "the Unknown sheet holds the sessions without a space and its title ends in nothing" do
      expect(sheets["Unknown"][1]).to eq(["Certifications granted in "])
      expect(sheets["Unknown"][7..]).to eq(
        [["Laser", 0, 0, 0, 0, 0, 0], ["Saw", 0, 0, 1, 1, 1, 1], ["Total", 0, 0, 1, 1, 1, 1]]
      )
    end

    it "the total sheet adds every space" do
      expect(sheets["total"][1]).to eq(["Certifications granted in total"])
      expect(sheets["total"][7..]).to eq(
        [["Laser", 1, 2, 1, 1, 2, 3], ["Saw", 0, 0, 1, 1, 1, 1], ["Total", 1, 2, 2, 2, 3, 4]]
      )
    end

    it "orders the space sheets by name descending, with the unknown sheet last and the total sheet after it" do
      beta = create(:space, name: "Beta")
      cert(create(:training_session, space: beta, training: saw, created_at: march_10), "P5")
      expect(sheets.keys).to eq(%w[Beta Alpha Unknown total])
    end

    it "with no certificates in the range is a single total sheet with only a Total row" do
      rows = grid(described_class.generate_certifications_report(DateTime.new(2019, 1, 1), DateTime.new(2019, 1, 31)))
      expect(rows.keys).to eq(["total"])
      expect(rows["total"].last).to eq(["Total", 0, 0])
    end
  end

  describe ".generate_new_users_report" do
    on_a_server_in_another_zone

    before do
      gina = student("Gina Genie", gender: "Female")
      gina.update_columns(faculty: "Génie", email: "gina@example.test", username: "gina")
      cam = create(:user, name: "Cam Community", created_at: march_10, gender: "Male",
                          email: "cam@example.test", username: "cam")
      cam.update_columns(faculty: "", program: "", year_of_study: nil)
      student("Mo Master", program: "Master of Arts", faculty: "Arts", gender: "Male",
                           email: "mo@example.test", username: "mo")
      student("Phil Doc", program: "PhD Physics", faculty: "Science", gender: "Other",
                          email: "phil@example.test", username: "phil")
      create(:user, name: "Early Bird", created_at: Time.utc(2026, 2, 1))
    end

    let(:sheets) { grid(described_class.generate_new_users_report(from, to)) }

    it "has Demographics, Faculties and Report sheets" do
      expect(sheets.keys).to eq(%w[Demographics Faculties Report])
    end

    it "Demographics: total, year of study (a blank year counts as 0), level and gender" do
      rows = sheets["Demographics"]
      expect(rows[0..9]).to eq(
        [["New Users Breakdown"], ["From", "2026-03-01"], ["To", "2026-03-31"], [],
         ["Total new users", 4], [], ["Year of Study"], [0, 1], [2020, 3], []]
      )
      expect(rows[10]).to eq(["Level of Study"])
      expect(rows[11..12]).to contain_exactly(["Undergrad", 3], ["Community member", 1])
      expect(rows[13..]).to eq([[], ["Gender"], ["Female", 1], ["Male", 2], ["Other", 1]])
    end

    it "Faculties: each faculty under its English name, a French one merged into it and a blank one as None" do
      student("Eli Engineer").update_columns(faculty: "Engineering")
      student("Edna Educ").update_columns(faculty: "Éducation")
      student("Ed Educ").update_columns(faculty: "Education")
      faculty = blocks(grid(described_class.generate_new_users_report(from, to))["Faculties"])[1]
      expect(faculty.first(2)).to eq([["By Faculty"], ["Faculty", "New Users"]])
      # the rows add up to the total
      expect(faculty[2..]).to contain_exactly(
        ["Arts", 1], ["Science", 1], ["None", 1], ["Engineering", 2], ["Education", 2], ["Total", 7]
      )
    end

    it "Faculties: departments by level, then programs ordered by count, a blank program as Blank - No Program" do
      rows = blocks(sheets["Faculties"])
      department = rows[2]
      expect(department[0..1]).to eq([["By Department"], ["Department", "New Users", nil, "Level"]])
      expect(department[2..]).to contain_exactly(
        ["EECS", 1, nil, "Bachelors"], ["Other Departments", 1, nil, "Masters"],
        ["Other Departments", 1, nil, "Doctorate"], ["Other Departments", 1, nil, "None"]
      )
      programs = rows[3]
      expect(programs.first).to eq(["By program"])
      expect(programs.drop(1)).to contain_exactly(
        ["BASc in Software Engineering", 1], ["Master of Arts", 1], ["PhD Physics", 1], ["Blank - No Program", 1]
      )
    end

    it "Report: identity counts named as on Demographics, then a user table with every value under its header" do
      rows = sheets["Report"]
      expect(rows.first(3)).to eq([["New Users"], ["From", "2026-03-01"], ["To", "2026-03-31"]])
      expect(rows).to include(["Overview"], ["Undergrad", 3], ["Community member", 1])
      header = rows.index(["Name", "Username", "Email", "Gender", "Identity", "Faculty", "Year of Study", "Student ID", "Joined on"])
      expect(header).to be_present
      body = rows[(header + 1)..]
      expect(body.size).to eq(4)
      expect(body).to all(have_attributes(size: 9))
      gina = body.find { |r| r.first == "Gina Genie" }
      expect(gina).to eq(["Gina Genie", "gina", "gina@example.test", "Female", "Undergrad", "Génie", 2020,
                          User.find_by(username: "gina").student_id, "2026-03-10 11:00"])
      cam = body.find { |r| r.first == "Cam Community" }
      expect(cam).to eq(["Cam Community", "cam", "cam@example.test", "Male", "Community member", nil, nil,
                         nil, "2026-03-10 11:00"])
    end

    it "counts users with a missing or blank identity in one None row on Demographics and Report" do
      student("Ivy Unknown").update_columns(identity: nil)
      student("Bea Blank").update_columns(identity: "")
      book = grid(described_class.generate_new_users_report(from, to))
      expect(book["Demographics"].count { |row| row.first == "None" }).to eq(1)
      expect(book["Demographics"]).to include(["None", 2])
      expect(book["Report"].count { |row| row.first == "None" }).to eq(1)
      expect(book["Report"]).to include(["None", 2])
      ivy = book["Report"].find { |row| row.first == "Ivy Unknown" }
      expect(ivy[4]).to eq("None")
    end

    it "includes soft-deleted users and excludes users outside the range" do
      create(:user, name: "Gone Gary", created_at: march_10).soft_delete!
      expect(grid(described_class.generate_new_users_report(from, to))["Demographics"]).to include(["Total new users", 5])
    end

    it "an empty range still gives the three sheets with zero totals" do
      empty = grid(described_class.generate_new_users_report(DateTime.new(2019, 1, 1), DateTime.new(2019, 1, 2)))
      expect(empty["Demographics"]).to include(["Total new users", 0])
      expect(empty["Faculties"]).to include(["Total", 0])
      expect(empty["Report"].last).to eq(["Name", "Username", "Email", "Gender", "Identity", "Faculty", "Year of Study", "Student ID", "Joined on"])
    end
  end

  describe ".generate_training_attendees_report" do
    on_a_server_in_another_zone

    let!(:alpha) { create(:space, name: "Alpha") }
    let(:laser) { create(:training, name_en: "Laser", name: "Laser") }

    let(:teacher) { create(:user, :staff, name: "Ina Instructor") }
    let(:lena) { create(:user, :student, name: "Lena Learner", email: "lena@example.test", student_id: "012345678") }

    def attend(user, session, at)
      create(:certification, user: user, training_session: session, training: session.training, created_at: at)
    end

    it "lists attendees, then monthly and weekly averages of attendees per session" do
      session = create(:training_session, space: alpha, training: laser, user: teacher, course: "MCG1", created_at: march_10)
      attend(lena, session, march_10)
      attend(create(:user, name: "Max Mate", email: "max@example.test"), session, march_10)
      rows = grid(described_class.generate_training_attendees_report(from, to))["Report - Alpha"]
      expect(rows.first(5)).to eq(
        [["Training Attendees - Alpha"], ["From", "2026-03-01"], ["To", "2026-03-31"], [],
         ["Student ID", "Name", "Email Address", "Certification Type", "Certification Date", "Instructor", "Course",
          "Facility"]]
      )
      stamp = "2026-03-10 11:00" # Toronto time
      # every value sits under its own header; a student id keeps its leading zero
      expect(rows[5..6]).to contain_exactly(
        ["012345678", "Lena Learner", "lena@example.test", "Laser", stamp, "Ina Instructor", "MCG1", "Alpha"],
        [nil, "Max Mate", "max@example.test", "Laser", stamp, "Ina Instructor", "MCG1", "Alpha"]
      )
      expect(rows[8..9]).to eq([["Month", "March 2026"], ["Month average of attendees per sessions", 2]])
      expect(rows[11]).to eq(
        ["Week", "2026-02-23 to 2026-03-01", "2026-03-02 to 2026-03-08", "2026-03-09 to 2026-03-15",
         "2026-03-16 to 2026-03-22", "2026-03-23 to 2026-03-29", "2026-03-30 to 2026-04-05"]
      )
      expect(rows[12]).to eq(["Week average of attendees per sessions", 0, 0, 2, 0, 0, 0])
    end

    it "a month without certificates averages 0.0, and averages have one decimal place" do
      first = create(:training_session, space: alpha, training: laser, created_at: march_10)
      second = create(:training_session, space: alpha, training: laser, created_at: march_10 + 1.day)
      attend(lena, first, march_10)
      attend(create(:user), first, march_10)
      attend(create(:user), second, march_10 + 1.day)
      package = described_class.generate_training_attendees_report(from, DateTime.new(2026, 4, 30))
      rows = grid(package)["Report - Alpha"]
      month = rows.index { |r| r.first == "Month" }
      expect(rows[month]).to eq(["Month", "March 2026", "April 2026"])
      # 3 certificates over 2 sessions; April has none
      expect(rows[month + 1]).to eq(["Month average of attendees per sessions", 1.5, 0.0])
      expect(rows[month + 1].drop(1)).to all(be_a(Float))
      styles = package.workbook.styles
      averages = package.workbook.worksheets.first.rows.select { |r| r.cells.first&.value.to_s.include?("average") }
      expect(averages.size).to eq(2)
      formats = averages.flat_map { |r| r.to_a.drop(1) }.map do |cell|
        num_fmt_id = styles.cellXfs[cell.style].numFmtId
        styles.numFmts.find { |f| f.numFmtId == num_fmt_id }&.formatCode
      end
      expect(formats).to all(eq("0.0"))
    end

    it "a custom range has a column for every month it overlaps, the partial ones at both ends included" do
      march = create(:training_session, space: alpha, training: laser, created_at: march_10)
      attend(lena, march, march_10)
      april = create(:training_session, space: alpha, training: laser, created_at: Time.utc(2026, 4, 10, 15))
      attend(lena, april, Time.utc(2026, 4, 10, 15))
      attend(create(:user), april, Time.utc(2026, 4, 10, 15))
      rows = grid(described_class.generate_training_attendees_report(DateTime.new(2026, 3, 5), DateTime.new(2026, 4, 20)))
      sheet = rows["Report - Alpha"]
      month = sheet.index(["Month", "March 2026", "April 2026"])
      expect(month).to be_present
      expect(sheet[month + 1]).to eq(["Month average of attendees per sessions", 1, 2])
    end

    it "names each month with its year, so a range over a year does not repeat a month name" do
      session = create(:training_session, space: alpha, training: laser, created_at: Time.utc(2027, 1, 15, 15))
      attend(lena, session, Time.utc(2027, 1, 15, 15))
      sheet = grid(described_class.generate_training_attendees_report(DateTime.new(2026, 12, 1), DateTime.new(2027, 12, 31)))["Report - Alpha"]
      month = sheet.index { |r| r.first == "Month" }
      expect(sheet[month]).to eq(["Month", "December 2026", *Date::MONTHNAMES.drop(1).map { |m| "#{m} 2027" }])
      expect(sheet[month + 1]).to eq(["Month average of attendees per sessions", 0.0, 1.0, *[0.0] * 11])
    end

    it "a range within one month has that month's column, and a column for every week it overlaps" do
      session = create(:training_session, space: alpha, training: laser, created_at: march_10)
      attend(lena, session, march_10)
      sheet = grid(described_class.generate_training_attendees_report(DateTime.new(2026, 3, 5), DateTime.new(2026, 3, 20)))["Report - Alpha"]
      expect(sheet).to include(["Month", "March 2026"], ["Month average of attendees per sessions", 1])
      expect(sheet).to include(
        ["Week", "2026-03-02 to 2026-03-08", "2026-03-09 to 2026-03-15", "2026-03-16 to 2026-03-22"],
        ["Week average of attendees per sessions", 0, 1, 0]
      )
    end

    it "the last days of the range fall in the week that holds them" do
      session = create(:training_session, space: alpha, training: laser, created_at: Time.utc(2026, 4, 29, 12))
      attend(lena, session, Time.utc(2026, 4, 29, 12))
      sheet = grid(described_class.generate_training_attendees_report(from, DateTime.new(2026, 4, 30)))["Report - Alpha"]
      week = sheet.find { |r| r.first == "Week" }
      expect(week.last).to eq("2026-04-27 to 2026-05-03")
      expect(sheet.last).to eq(["Week average of attendees per sessions"] + [0] * (week.size - 2) + [1])
    end

    it "a session without a space gets its own sheet named with a trailing dash" do
      session = create(:training_session, space: alpha, training: laser, created_at: march_10)
      session.update_columns(space_id: nil)
      attend(lena, session, march_10)
      rows = grid(described_class.generate_training_attendees_report(from, to))
      expect(rows.keys).to eq(["Report - "])
      expect(rows["Report - "].first).to eq(["Training Attendees - "])
      expect(rows["Report - "][5]).to eq(["012345678", "Lena Learner", "lena@example.test", "Laser",
                                          session.created_at.strftime("%Y-%m-%d %H:%M"), session.user.name])
    end
  end

  describe ".generate_new_projects_report" do
    it "counts categories, equipment, licenses and share types, then lists each project" do
      one = create(:repository, title: "Robot Arm", created_at: march_10)
      create(:category, repository: one, name: "Robotics")
      create(:equipment, repository: one, name: "3D Printer")
      create(:equipment, repository: one, name: "Laser Cutter")
      two = create(:repository, title: "Lamp", created_at: march_10)
      create(:category, repository: two, name: "Robotics")
      create(:repository, created_at: Time.utc(2026, 5, 1))
      sheets = grid(described_class.generate_new_projects_report(from, to))
      expect(sheets.keys).to eq(%w[Statistics Report])
      stats = blocks(sheets["Statistics"])
      expect(stats[0]).to eq([["Various statistics"], ["From", "2026-03-01"], ["To", "2026-03-31"], ["Total New Projects", 2]])
      expect(stats[1]).to eq([["Categories"], ["Robotics", 2], ["Total", 2]])
      expect(stats[2].first).to eq(["Equipment usage"])
      expect(stats[2].drop(1)).to contain_exactly(["3D Printer", 1], ["Laser Cutter", 1], ["Total", 2])
      expect(stats[3]).to eq([["Licenses"], [nil, 2], ["Total", 2]])
      expect(stats[4]).to eq([["Share types"], ["public", 2], ["Total", 2]])
      report = sheets["Report"]
      expect(report[4]).to eq(%w[Title Users URL Categories])
      row = report.find { |r| r.first == "Robot Arm" }
      expect(row[2]).to end_with("/#{one.id}")
      expect(report.find { |r| r.first == "Lamp" }[3]).to eq("Robotics")
    end

    it "with no projects has zero totals and only the header row" do
      sheets = grid(described_class.generate_new_projects_report(from, to))
      expect(sheets["Statistics"]).to include(["Total New Projects", 0], ["Categories"], ["Total", 0])
      expect(sheets["Report"].last).to eq(%w[Title Users URL Categories])
    end
  end

  describe ".generate_kit_purchased_report" do
    it "lists delivered and undelivered kits with the buyer and a Delivered column" do
      project = create(:proficient_project, title: "Blinky")
      create(:project_kit, proficient_project: project, user: create(:user, name: "Kit Kat"), created_at: march_10)
      create(:project_kit, :delivered, proficient_project: project, user: create(:user, name: "Del Ivered"), created_at: march_10)
      rows = grid(described_class.generate_kit_purchased_report(from, to))["Report"]
      expect(rows[4]).to eq(["Kit name", "User", "Date", "Delivery Status"])
      expect(rows[5..].map { |r| [r[0], r[1], r[3]] }).to contain_exactly(
        ["Blinky", "Kit Kat", "Not yet delivered"], ["Blinky", "Del Ivered", "Delivered"]
      )
    end
  end

  describe ".generate_peak_hours_report" do
    it "an empty range lists one row per day, with no hour columns" do
      rows = grid(described_class.generate_peak_hours_report(DateTime.new(2026, 3, 1), DateTime.new(2026, 3, 2)))["Sheet1"]
      expect(rows[4]).to eq(["Date"])
      expect(rows[5..]).to eq([["2026-03-01"], ["2026-03-02"]])
    end

    it "an inverted range gives no day rows" do
      rows = grid(described_class.generate_peak_hours_report(to, from))["Sheet1"]
      expect(rows).to eq([["Visitors by Hour"], ["From", "2026-03-31"], ["To", "2026-03-01"], [], ["Date"]])
    end

    context "on a server in another time zone" do
      on_a_server_in_another_zone

      it "counts each visit under its hour and day in Toronto time" do
        create(:lab_session, sign_in_time: march_10, created_at: march_10)
        create(:lab_session, sign_in_time: Time.utc(2026, 3, 11, 2, 15), created_at: march_10)
        rows = grid(described_class.generate_peak_hours_report(DateTime.new(2026, 3, 10), DateTime.new(2026, 3, 11).end_of_day))["Sheet1"]
        # 15:00 UTC is 11:00 in Toronto, and 02:15 UTC on the 11th is 22:15 on the 10th
        expect(rows[4]).to eq(["Date", *(11..22).map { |h| "%02i:00" % h }])
        expect(rows[5]).to eq(["2026-03-10", 1, *[0] * 10, 1])
        expect(rows[6]).to eq(["2026-03-11", *[0] * 12])
      end

      it "lists the days from the From date to the To date, for a range that ends now in the Toronto evening" do
        # 21:00 in Toronto is 01:00 UTC on the next day
        rows = grid(described_class.generate_peak_hours_report(DateTime.new(2026, 3, 9), Time.zone.local(2026, 3, 10, 21)))["Sheet1"]
        expect(rows[2]).to eq(%w[To 2026-03-10])
        expect(rows[5..]).to eq([["2026-03-09"], ["2026-03-10"]])
      end

      it "counts only the visits of the listed days in Toronto, so every hour column belongs to a listed day" do
        # 01:00 UTC on the 10th is 21:00 on the 9th in Toronto, before the first
        # listed day; 02:00 UTC on the 11th is 22:00 on the 10th
        create(:lab_session, sign_in_time: Time.utc(2026, 3, 10, 1), created_at: march_10)
        create(:lab_session, sign_in_time: march_10, created_at: march_10)
        create(:lab_session, sign_in_time: Time.utc(2026, 3, 11, 2), created_at: march_10)
        rows = grid(described_class.generate_peak_hours_report(DateTime.new(2026, 3, 10), DateTime.new(2026, 3, 10).end_of_day))["Sheet1"]
        expect(rows[4]).to eq(["Date", *(11..22).map { |h| "%02i:00" % h }])
        expect(rows[5..]).to eq([["2026-03-10", 1, *[0] * 10, 1]])
      end

      it "adds up the visits of the hour that repeats when daylight saving time ends" do
        # 05:30 and 06:30 UTC on 2026-11-01 are both 01:30 in Toronto (EDT, then EST)
        create(:lab_session, sign_in_time: Time.utc(2026, 11, 1, 5, 30))
        create(:lab_session, sign_in_time: Time.utc(2026, 11, 1, 6, 30))
        rows = grid(described_class.generate_peak_hours_report(DateTime.new(2026, 11, 1), DateTime.new(2026, 11, 1).end_of_day))["Sheet1"]
        expect(rows[4..]).to eq([%w[Date 01:00], ["2026-11-01", 2]])
      end
    end
  end

  describe ".generate_space_present_users_report" do
    on_a_server_in_another_zone

    it "stamps the report with the current time in Toronto and lists nobody when the space is empty" do
      # 03:30:45 UTC on the 11th is still the evening of the 10th in Toronto
      travel_to(Time.utc(2026, 3, 11, 3, 30, 45)) do
        space = create(:space)
        rows = grid(described_class.generate_space_present_users_report(space.id))["Report"]
        expect(rows).to eq([["Present Users"], ["Date", "2026-03-10 23:30:45"], [], %w[Name Email]])
      end
    end
  end

  describe "helpers no action calls" do
    it "sum_by_key adds one key over a list of hashes" do
      expect(described_class.sum_by_key([{ a: 1 }, { a: 2 }, { a: 4 }], :a)).to eq(7)
      expect(described_class.sum_by_key([], :a)).to eq(0)
    end

    it "student_id_as_text types only the Student ID column as text, wherever it is" do
      expect(described_class.student_id_as_text(["Name", "Student ID", "Date"])).to eq([nil, :string, nil])
      expect(described_class.student_id_as_text(%w[Name Date])).to eq([nil, nil])
    end

    it "title writes a bold underlined row; table_header writes a bold row" do
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "S") do |sheet|
        described_class.title(sheet, "T")
        described_class.table_header(sheet, %w[A B])
        described_class.push_hash(sheet, { "k" => 1 })
      end
      expect(grid(package)["S"]).to eq([["T"], %w[A B], ["k", 1]])
    end

    describe ".get_visitors" do
      let(:alpha) { create(:space, name: "Alpha") }

      it "returns an empty tally when nobody signed in during the range" do
        expect(described_class.get_visitors(from, to)).to eq(
          unique: 0, total: 0, spaces: {}, identities: {}, faculties: {}, genders: {}
        )
      end

      it "tallies unique visitors and visits by space, identity, faculty and gender" do
        ids = { "undergrad" => "Undergraduate", "grad" => "Graduate", "faculty_member" => "Faculty Member",
                "staff_member" => "Staff Member", "community_member" => "Community Member", "mystery" => "Unknown" }
        ids.each_key do |identity|
          user = create(:user, gender: "Male")
          user.update_columns(identity: identity, faculty: identity == "undergrad" ? "" : "Arts")
          create(:lab_session, space: alpha, user: user, sign_in_time: march_10)
        end
        again = User.find_by(identity: "undergrad")
        beta = create(:space, name: "Beta")
        twin = create(:user, gender: "Female")
        twin.update_columns(identity: "undergrad", faculty: "Arts")
        create(:lab_session, space: beta, user: twin, sign_in_time: march_10)
        create(:lab_session, space: alpha, user: again, sign_in_time: march_10 + 1.hour)
        create(:lab_session, space: alpha, user: again, sign_in_time: Time.utc(2026, 5, 1))
        tally = described_class.get_visitors(from, to)
        expect(tally[:unique]).to eq(7)
        expect(tally[:total]).to eq(8)
        expect(tally[:identities].keys).to match_array(ids.values)
        expect(tally[:identities]["Undergraduate"]).to eq(
          unique: 2, total: 3, faculties: { "Unknown" => { unique: 1, total: 2 }, "Arts" => { unique: 1, total: 1 } }
        )
        expect(tally[:faculties]).to eq("Unknown" => { unique: 1, total: 2 }, "Arts" => { unique: 6, total: 6 })
        expect(tally[:genders]).to eq("Male" => { unique: 6, total: 7 }, "Female" => { unique: 1, total: 1 })
        expect(tally[:spaces].keys).to eq(%w[Alpha Beta])
        expect(tally[:spaces]["Alpha"].slice(:unique, :total)).to eq(unique: 6, total: 7)
        expect(tally[:spaces]["Beta"].slice(:unique, :total)).to eq(unique: 1, total: 1)
        expect(tally[:spaces]["Alpha"][:genders]).to eq("Male" => { unique: 6, total: 7 })
        expect(tally[:spaces]["Alpha"][:faculties]["Arts"]).to eq(unique: 5, total: 5)
      end

      it "adds up visitors who share a space, identity and faculty but not a gender" do
        %w[Male Female].each do |gender|
          user = create(:user, gender: gender)
          user.update_columns(identity: "grad", faculty: "Arts")
          create(:lab_session, space: alpha, user: user, sign_in_time: march_10)
        end
        tally = described_class.get_visitors(from, to)
        arts = { "Arts" => { unique: 2, total: 2 } }
        expect(tally[:spaces]["Alpha"][:identities]["Graduate"]).to eq(unique: 2, total: 2, faculties: arts)
        expect(tally[:identities]["Graduate"]).to eq(unique: 2, total: 2, faculties: arts)
        expect(tally[:spaces]["Alpha"][:genders].keys).to match_array(%w[Male Female])
      end
    end

    describe ".get_new_projects" do
      it "gives one row per repository with both a category and equipment, the equipment name shadowing the category name" do
        repo = create(:repository, created_at: march_10)
        create(:category, repository: repo, name: "Cat")
        create(:equipment, repository: repo, name: "Eq1")
        create(:equipment, repository: repo, name: "Eq2")
        no_equipment = create(:repository, created_at: march_10)
        create(:category, repository: no_equipment, name: "Lonely")
        rows = described_class.get_new_projects(from, to).to_a
        expect(rows.map { |r| [r["id"], r["created_month"], r["created_year"], r["share_type"], r["name"]] }).to contain_exactly(
          [repo.id, "03", "2026", "public", "Eq1"], [repo.id, "03", "2026", "public", "Eq2"]
        )
      end
    end
  end
end
