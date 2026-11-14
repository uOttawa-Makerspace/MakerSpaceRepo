# frozen_string_literal: true

require "rails_helper"

# Text that people enter (names, emails, faculties, programs, titles, course
# codes and the like) is written to the report workbooks as text cells, so a
# value that looks like a number or a formula opens as it was entered.
RSpec.describe ReportGenerator do
  include ActiveSupport::Testing::TimeHelpers

  let(:march_10) { Time.utc(2026, 3, 10, 15, 0, 0) }
  let(:from) { Time.zone.local(2026, 3, 1) }
  let(:to) { Time.zone.local(2026, 3, 31) }
  let(:formula) { '=HYPERLINK("http://example.test","x")' }

  # [value, Roo cell type, formula?] for every cell of every sheet.
  def cells(package)
    file = Tempfile.new(["text-cells", ".xlsx"])
    file.binmode
    file.write(package.to_stream.read)
    file.flush
    xlsx = Roo::Excelx.new(file.path)
    xlsx.sheets.flat_map { |name| sheet_cells(xlsx.sheet(name)) }
  ensure
    file&.close!
  end

  def sheet_cells(sheet)
    return [] unless sheet.first_row

    (sheet.first_row..sheet.last_row).to_a.product((sheet.first_column..sheet.last_column).to_a).map do |row, column|
      [sheet.cell(row, column), sheet.celltype(row, column), sheet.formula?(row, column)]
    end
  end

  def text_cells(package)
    cells(package).select { |_, type, formula| type == :string && !formula }.map(&:first)
  end

  def person(**columns)
    create(:user, :student, created_at: march_10).tap { |user| user.update_columns(**columns) }
  end

  it "new users: the name, username, email, gender, identity, faculty, program and student number" do
    person(name: formula, username: "+1+1", email: "-101", gender: "-102", identity: "-103",
           faculty: "@SUM(1)", program: "-104", student_id: "0105")
    text = text_cells(described_class.generate_new_users_report(from, to))
    expect(text).to include(formula, "+1+1", "-101", "-102", "-103", "@SUM(1)", "-104", "0105")
  end

  it "new users: the year of study and the counts stay numbers" do
    person(name: "Ada", year_of_study_entered: "3")
    report = cells(described_class.generate_new_users_report(from, to))
    expect(report).to include([3, :float, false], ["Ada", :string, false])
    expect(report).to include(["Total new users", :string, false], [1, :float, false])
  end

  it "new users: a year of study that is not a number is a text row label, a numbered one stays a number" do
    person(year_of_study_entered: "=1+1")
    person(year_of_study_entered: "1e3")
    person(year_of_study_entered: "3")
    report = cells(described_class.generate_new_users_report(from, to))
    expect(report).to include(["=1+1", :string, false], ["1e3", :string, false], [3, :float, false])
  end

  it "visitors: the identity, gender, faculty and program" do
    user = person(identity: "-201", gender: "-202", faculty: "-203", program: "-204")
    create(:lab_session, user: user, space: create(:space, name: "Alpha"), created_at: march_10)
    # the Programs sheet lists a program without its leading sign
    expect(text_cells(described_class.generate_visitors_report(from, to)))
      .to include("-201", "-202", "-203", "204")
  end

  describe "training reports" do
    let(:space) { create(:space, name: "-301") }
    let(:training) { create(:training, name: "-302", name_en: "-302") }
    let(:instructor) { create(:user, :staff).tap { |user| user.update_columns(name: "-303") } }
    let(:session) do
      create(:training_session, space: space, training: training, user: instructor, course: "-304",
                                level: "-305", created_at: march_10)
    end
    let(:learner) { person(name: formula, email: "-306", student_id: "0307") }

    before do
      session.users << learner
      create(:certification, user: learner, training_session: session, training: training, created_at: march_10)
    end

    it "trainings: the training, level, course, instructor and space" do
      expect(text_cells(described_class.generate_trainings_report(from, to)))
        .to include("-302", "-305", "-304", "-303", "-301")
    end

    it "certifications: the training and the course" do
      expect(text_cells(described_class.generate_certifications_report(from, to))).to include("-302", "-304")
    end

    it "attendees: the name, email, training, instructor, course, facility and student number" do
      expect(text_cells(described_class.generate_training_attendees_report(from, to)))
        .to include(formula, "-306", "-302", "-303", "-304", "-301", "0307")
    end

    it "one session: the training, space, instructor, course and each trainee's name and email" do
      expect(text_cells(described_class.generate_training_session_report(session.id)))
        .to include("-302", "-301", "-303", "-304", formula, "-306")
    end
  end

  it "new projects: the categories, equipment, licenses, share types, titles and users" do
    repository = create(:repository, title: "-401", created_at: march_10)
    repository.update_columns(license: "-402", share_type: "-403")
    repository.users << person(name: "-404")
    create(:category, repository: repository, name: "-405")
    create(:equipment, repository: repository, name: "-406")
    expect(text_cells(described_class.generate_new_projects_report(from, to)))
      .to include("-401", "-402", "-403", "-404", "-405", "-406")
  end

  it "present users: the name and email" do
    space = create(:space)
    create(:lab_session, space: space, user: person(name: formula, email: "-501"),
                         sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
    expect(text_cells(described_class.generate_space_present_users_report(space.id))).to include(formula, "-501")
  end

  it "purchased kits: the kit and the buyer" do
    create(:project_kit, proficient_project: create(:proficient_project, title: "-601"),
                         user: person(name: "-602"), created_at: march_10)
    expect(text_cells(described_class.generate_kit_purchased_report(from, to))).to include("-601", "-602")
  end
end
