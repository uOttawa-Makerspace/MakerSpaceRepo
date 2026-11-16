# frozen_string_literal: true

require "rails_helper"

# POST /admin/uni_programs/import_programs: upload of the programs csv.
RSpec.describe "Admin uni programs import", type: :request do
  include SpacesSpecHelpers

  let(:header) { "program,level,faculty,department" }

  def upload(body, name: "programs.csv", allow_new_programs: nil)
    file = Rack::Test::UploadedFile.new(StringIO.new(body), "text/csv", original_filename: name)
    post "/admin/uni_programs/import_programs", params: { file: file, allow_new_programs: allow_new_programs }
  end

  def csv(*rows) = ([header] + rows).join("\n")

  def programs = UniProgram.order(:program).map { |p| [p.program, p.level, p.faculty, p.department] }

  context "as an admin" do
    before do
      sign_in_as(:admin)
      create(:uni_program, program: "Computer Science", level: "Bachelor's", faculty: "Engineering", department: "Non-Engineering")
    end

    it "adds new programs, updates a changed department in place and reports the counts" do
      upload csv("Computer Science,Bachelor's,Engineering,EECS", "Physics,Master's,Engineering,Physics")

      expect(response).to redirect_to(admin_uni_programs_index_path)
      expect(flash[:notice]).to eq("Upload complete, 2 programs found (1 added, 1 updated, 0 restored, 0 retired)")
      expect(programs).to eq([["Computer Science", "Bachelor's", "Engineering", "EECS"],
                              ["Physics", "Master's", "Engineering", "Physics"]])
    end

    it "marks programs missing from the file inactive instead of deleting them" do
      upload csv("Physics,Master's,Engineering,Physics")

      expect(flash[:notice]).to include("1 added, 0 updated, 0 restored, 1 retired")
      expect(UniProgram.pluck(:program)).to contain_exactly("Computer Science", "Physics")
      expect(UniProgram.active.pluck(:program)).to eq(["Physics"])
    end

    it "brings a retired program back when a later file lists it again" do
      upload csv("Physics,Master's,Engineering,Physics")
      upload csv("Computer Science,Bachelor's,Engineering,EECS")

      expect(flash[:notice]).to include("0 added, 0 updated, 1 restored, 1 retired")
      expect(UniProgram.count).to eq(2)
      expect(UniProgram.active.map { |p| [p.program, p.department] }).to eq([["Computer Science", "EECS"]])
    end

    it "changes nothing when the same file is imported twice" do
      body = csv("Computer Science,Bachelor's,Engineering,EECS", "Physics,Master's,Engineering,Physics")
      upload body
      first = UniProgram.order(:program).map(&:attributes)
      upload body

      expect(flash[:notice]).to eq("Upload complete, 2 programs found (0 added, 0 updated, 0 restored, 0 retired)")
      expect(UniProgram.order(:program).map(&:attributes)).to eq(first)
    end

    it "counts a program listed twice in the file once" do
      upload csv("Physics,Master's,Engineering,Physics", "Physics,Master's,Engineering,Physics")

      expect(flash[:notice]).to include("2 programs found (1 added")
      expect(UniProgram.where(program: "Physics").count).to eq(1)
    end

    it "keeps the same program at another level or faculty as its own entry" do
      upload csv("Physics,Master's,Engineering,Physics", "Physics,Doctorate,Engineering,Physics")

      expect(UniProgram.where(program: "Physics").pluck(:level)).to contain_exactly("Master's", "Doctorate")
    end

    it "trims whitespace around the values" do
      upload csv("  Physics , Master's ,Engineering,  Physics ")

      expect(programs).to include(["Physics", "Master's", "Engineering", "Physics"])
    end

    it "reads accented text" do
      upload csv("B.A. spécialisé Lettres françaises,Bachelor's,Engineering,Non-Engineering")

      expect(UniProgram.active.pluck(:program)).to eq(["B.A. spécialisé Lettres françaises"])
    end

    it "rejects a file that is not a csv and changes nothing" do
      upload csv("Physics,Master's,Engineering,Physics"), name: "programs.txt"

      expect(flash[:alert]).to include("Unknown file extension")
      expect(programs.map(&:first)).to eq(["Computer Science"])
    end

    it "rejects a wrong header and changes nothing" do
      upload "program,faculty,level,department\nPhysics,Engineering,Master's,Physics"

      expect(flash[:alert]).to include("Wrong header")
      expect(programs.map(&:first)).to eq(["Computer Science"])
    end

    it "rejects an empty value, naming the line and column, and changes nothing" do
      upload csv("Physics,Master's,Engineering,Physics", "Chemistry,Master's,,Chemistry")

      expect(flash[:alert]).to include("line number 3, column faculty is empty")
      expect(programs.map(&:first)).to eq(["Computer Science"])
    end

    it "rejects an unknown faculty unless new programs are allowed" do
      upload csv("Magic,Master's,Wizardry,Magic")
      expect(flash[:alert]).to include("Unknown faculty Wizardry at line number 2")
      expect(programs.map(&:first)).to eq(["Computer Science"])

      upload csv("Magic,Master's,Wizardry,Magic"), allow_new_programs: "1"
      expect(UniProgram.active.pluck(:program)).to eq(["Magic"])
    end

    it "leaves the row without a faculty alone" do
      create(:uni_program, faculty: "", program: "Not listed")
      upload csv("Physics,Master's,Engineering,Physics")

      expect(UniProgram.unscoped.where(faculty: "").pluck(:program, :active)).to eq([["Not listed", true]])
    end
  end

  describe "retired programs on the index" do
    before do
      sign_in_as(:admin)
      create(:uni_program, program: "Current Program", faculty: "Engineering")
      create(:uni_program, program: "Retired Program", level: "Doctorate", faculty: "Engineering", active: false)
    end

    it "offers the new faculties box with the value 1 and no stray value" do
      get admin_uni_programs_index_path

      box = Nokogiri::HTML(response.body).at_css("input[type=checkbox][name=allow_new_programs]")
      expect(box["value"]).to eq("1")
      expect(box["class"]).to eq("form-check-input")
      expect(box["checked"]).to be_nil
    end

    it "lists inactive programs in their own section, apart from the active ones" do
      get admin_uni_programs_index_path

      expect(response.body).to include("Retired programs", "Retired Program", "Doctorate")
      expect(response.body.index("Current Program")).to be < response.body.index("Retired programs")
    end

    it "shows the section in French" do
      get admin_uni_programs_index_path, params: { locale: "fr" }

      expect(response.body).to include("Programmes retirés", "Retired Program")
    end

    it "shows no section when nothing is retired" do
      UniProgram.where(active: false).update_all(active: true)
      get admin_uni_programs_index_path

      expect(response.body).not_to include("Retired programs")
    end
  end

  it "keeps a signed-in non-admin out and changes nothing" do
    sign_in_as(:regular)
    create(:uni_program, faculty: "Engineering")
    upload csv("Physics,Master's,Engineering,Physics")

    expect(response).not_to have_http_status(:ok)
    expect(UniProgram.pluck(:program)).to eq(["MyString"])
  end
end
