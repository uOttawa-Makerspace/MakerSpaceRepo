# frozen_string_literal: true

require "rails_helper"

# Chunk 18: unit-level characterization of ReportGenerator (representative
# types; the controller-level contract is in
# spec/requests/admin_report_generator_request_spec.rb).
RSpec.describe ReportGenerator do
  include Chunk18Helpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:from) { DateTime.new(2026, 3, 1) }
  let(:to) { DateTime.new(2026, 3, 31) }

  def sheets_of(package)
    c18_xlsx_sheets(package.to_stream.read)
  end

  describe ".get_new_users" do
    it "returns users created inside the (inclusive) range as a relation" do
      inside = create(:user, created_at: march_10)
      create(:user, created_at: Time.utc(2026, 2, 28))
      create(:user, created_at: Time.utc(2026, 4, 2))
      expect(described_class.get_new_users(from, to)).to contain_exactly(inside)
    end
  end

  describe ".generate_new_users_report" do
    it "returns an Axlsx package with a Demographics sheet: total, year of study, level, gender" do
      create(:user, :student, created_at: march_10, year_of_study: 3, gender: "Female")
      create(:user, :student, created_at: march_10, year_of_study: 3, gender: "Male")
      package = described_class.generate_new_users_report(from, to)
      expect(package).to be_a(Axlsx::Package)
      rows = sheets_of(package).fetch("Demographics")
      expect(rows.first.first).to eq("New Users Breakdown")
      expect(rows[1].first(2)).to eq(%w[From 2026-03-01])
      expect(rows[2].first(2)).to eq(%w[To 2026-03-31])
      expect(rows).to include(["Total new users", 2])
      expect(rows).to include([3, 2]) # year of study 3 -> 2 users
      expect(rows).to include(["Undergrad", 2])
      expect(rows).to include(["Female", 1])
      expect(rows).to include(["Male", 1])
    end

    it "with no users in range still returns a Demographics sheet with Total new users 0" do
      rows = sheets_of(described_class.generate_new_users_report(from, to)).fetch("Demographics")
      expect(rows).to include(["Total new users", 0])
    end
  end

  describe ".generate_kit_purchased_report" do
    it "lists kit name, buyer, date and delivery status and honors the range" do
      buyer = create(:user, name: "Kit Buyer")
      kit = create(:project_kit, user: buyer, created_at: march_10)
      create(:project_kit, user: buyer, created_at: Time.utc(2026, 5, 1))
      rows = sheets_of(described_class.generate_kit_purchased_report(from, to)).fetch("Report")
      expect(rows[4]).to eq(["Kit name", "User", "Date", "Delivery Status"])
      expect(rows.size).to eq(6)
      expect(rows[5][0]).to eq(kit.proficient_project.title)
      expect(rows[5][1]).to eq("Kit Buyer")
      expect(rows[5][3]).to eq("Not yet delivered")
      expect(rows[5][2].to_date).to eq(Date.new(2026, 3, 10))
    end
  end

  describe ".generate_visitors_report" do
    it "makes an Overview sheet, a per-space sheet and a Programs sheet" do
      space = create(:space, name: "Unit Space")
      user = create(:user, :student, created_at: march_10)
      2.times { create(:lab_session, space: space, user: user, created_at: march_10) }
      sheets = sheets_of(described_class.generate_visitors_report(from, to))
      expect(sheets.keys).to eq(["Report", "Unit Space", "Programs"])
      expect(sheets["Report"]).to include(["CEED-Wide unique visitors", 1, nil, nil, nil, nil])
      expect(sheets["Report"]).to include(["CEED-Wide total visitors", 2, nil, nil, nil, nil])
    end

    it "with no visits still yields the Report and Programs sheets only" do
      expect(sheets_of(described_class.generate_visitors_report(from, to)).keys).to eq(%w[Report Programs])
    end
  end

  describe ".generate_trainings_report / certifications / training_attendees / new_projects" do
    let!(:space) { create(:space, name: "Unit Space") }
    let!(:training) { create(:training, name_en: "Unit Training") }
    let!(:session) { create(:training_session, space: space, training: training, created_at: march_10) }
    let!(:learner) { create(:user, :student, name: "Lena Learner", email: "lena@example.test") }

    before do
      session.users << learner
      create(:certification, user: learner, training_session: session, training: training,
                             space: space, created_at: march_10)
    end

    it "trainings: a workbook that names the training" do
      all_cells = sheets_of(described_class.generate_trainings_report(from, to)).values.flatten
      expect(all_cells).to include("Unit Training")
    end

    it "certifications: a workbook that names the training and the space" do
      all_cells = sheets_of(described_class.generate_certifications_report(from, to)).values.flatten
      expect(all_cells).to include("Unit Training")
    end

    it "training_attendees: one 'Report - <space>' sheet per space with a header and an attendee row" do
      sheets = sheets_of(described_class.generate_training_attendees_report(from, to))
      expect(sheets.keys).to eq(["Report - Unit Space"])
      rows = sheets["Report - Unit Space"]
      expect(rows.first.first).to eq("Training Attendees - Unit Space")
      expect(rows.flatten).to include("Lena Learner", "lena@example.test")
    end

    it "training_attendees: an empty range returns a package with no worksheets at all" do
      package = described_class.generate_training_attendees_report(DateTime.new(2019, 1, 1), DateTime.new(2019, 1, 2))
      expect(package.workbook.worksheets).to be_empty
    end

    it "new_projects: returns a package for an empty and for a populated range" do
      expect(described_class.generate_new_projects_report(from, to)).to be_a(Axlsx::Package)
      create(:repository, created_at: march_10)
      expect(described_class.generate_new_projects_report(from, to)).to be_a(Axlsx::Package)
    end
  end

  describe ".generate_peak_hours_report" do
    it "emits Date + one HH:00 column per hour in the observed min..max and a row per day" do
      create(:lab_session, sign_in_time: march_10, created_at: march_10)
      create(:lab_session, sign_in_time: march_10 + 2.hours, created_at: march_10)
      rows = sheets_of(described_class.generate_peak_hours_report(from, to)).fetch("Sheet1")
      hour = march_10.localtime.hour
      expect(rows[4].compact).to eq(["Date", "%02i:00" % hour, "%02i:00" % (hour + 1), "%02i:00" % (hour + 2)])
      day = rows.find { |r| r.first == "2026-03-10" }
      expect(day.first(4)).to eq(["2026-03-10", 1, 0, 1])
    end
  end

  describe ".generate_training_session_report" do
    it "lists type, location, date, instructor, course and the trainees (name, email)" do
      instructor = create(:user, :staff, name: "Ina Instructor")
      session = create(:training_session, user: instructor, course: "Intro", created_at: march_10)
      trainee = create(:user, name: "Tia Trainee", email: "tia@example.test")
      session.users << trainee
      rows = sheets_of(described_class.generate_training_session_report(session.id)).fetch("Report")
      expect(rows.first.first).to eq("Training Session")
      expect(rows[1]).to eq(["Training Type", session.training.name_en])
      expect(rows[2]).to eq(["Location", session.space.name])
      expect(rows[3]).to eq(["Date", march_10.in_time_zone.strftime("%Y-%m-%d %H:%M")]) # app time zone
      expect(rows[4]).to eq(["Instructor", "Ina Instructor"])
      expect(rows[5]).to eq(%w[Course Intro])
      expect(rows[6]).to eq(["Number of Trainees", 1])
      expect(rows[8]).to eq(%w[Name Email])
      expect(rows[9]).to eq(["Tia Trainee", "tia@example.test"])
    end

    it "raises RecordNotFound for an unknown session id" do
      expect { described_class.generate_training_session_report(0) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".generate_space_present_users_report" do
    it "lists only users currently signed in (sign_in in the past, sign_out in the future) at that space" do
      space = create(:space)
      here = create(:user, name: "Here Now", email: "here@example.test")
      gone = create(:user, name: "Already Gone")
      elsewhere = create(:user, name: "Other Space")
      create(:lab_session, space: space, user: here, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      create(:lab_session, space: space, user: gone, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
      create(:lab_session, space: create(:space), user: elsewhere, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
      rows = sheets_of(described_class.generate_space_present_users_report(space.id)).fetch("Report")
      expect(rows.first.first).to eq("Present Users")
      expect(rows[3]).to eq(%w[Name Email])
      expect(rows[4..]).to eq([["Here Now", "here@example.test"]])
    end
  end

  describe "program helpers" do
    it "get_program_department buckets programs by regex, defaulting to Other Departments" do
      expect(described_class.get_program_department("BASc in Mechanical Engineering")).to eq("Mechanical")
      expect(described_class.get_program_department("BASc in Software Engineering")).to eq("EECS")
      expect(described_class.get_program_department("BSc Computer Science")).to eq("EECS")
      expect(described_class.get_program_department("Civil Engineering")).to eq("Civil")
      expect(described_class.get_program_department("Biomedical Mechanical Engineering")).to eq("Mechanical")
      expect(described_class.get_program_department("Biotechnology")).to eq("Chemical & Biological")
      expect(described_class.get_program_department("Political Science")).to eq("Other Departments")
      expect(described_class.get_program_department(nil)).to eq("Other Departments")
    end

    it "get_study_level maps Bachelors / Masters / Doctorate / None" do
      expect(described_class.get_study_level("BASc in Software Engineering")).to eq("Bachelors")
      expect(described_class.get_study_level("Honours BSocSc Political Science")).to eq("Bachelors")
      expect(described_class.get_study_level("Master of Engineering")).to eq("Masters")
      expect(described_class.get_study_level("PhD in Chemistry")).to eq("Doctorate")
      expect(described_class.get_study_level("MBA")).to eq("None")
      expect(described_class.get_study_level(nil)).to eq("None")
    end

    it "categorize_programs counts Blank / Engineering / Non-Engineering / levels" do
      programs = { "" => 2, "BASc in Software Engineering" => 3, "Master of Arts" => 1, "BA History" => 4 }
      expect(described_class.categorize_programs(programs)).to eq(
        "Blank" => 2, "Engineering" => 3, "Non-Engineering" => 7,
        "Bachelors" => 7, "Masters" => 1, "Doctorate" => 0
      )
    end

    it "categorize_programs misses PhD programs although get_study_level calls them Doctorate" do
      # WART(D-R08): categorize_programs looks for the literal "Doctorate" while get_study_level also accepts "PhD|Doctor", so PhD students are counted under no level in the Programs breakdown
      expect(described_class.get_study_level("PhD in Chemistry")).to eq("Doctorate")
      expect(described_class.categorize_programs({ "PhD in Chemistry" => 5 })["Doctorate"]).to eq(0)
    end
  end

  describe "sheet helpers" do
    it "header writes title, From and To (then a blank spacer row)" do
      package = Axlsx::Package.new
      package.workbook.add_worksheet(name: "S") { |sheet| described_class.header(sheet, "Title", from, to) }
      expect(sheets_of(package).fetch("S")).to eq(
        [["Title", nil], ["From", "2026-03-01"], ["To", "2026-03-31"]] # trailing blank spacer row is dropped by the reader
      )
    end
  end
end
