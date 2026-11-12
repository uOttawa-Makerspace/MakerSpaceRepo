require "rails_helper"

RSpec.describe UniProgram, type: :model do
  describe "validations" do
    it "requires a program" do
      record = build(:uni_program, program: nil)
      expect(record).not_to be_valid
      expect(record.errors[:program]).to be_present
    end

    it "is valid with a program" do
      expect(build(:uni_program)).to be_valid
    end
  end

  describe "default scope" do
    it "excludes rows whose faculty is the empty string" do
      kept = create(:uni_program, faculty: "Engineering", program: "CS")
      create(:uni_program, faculty: "", program: "Undeclared")

      expect(UniProgram.all.map(&:program)).to eq([kept.program])
    end
  end

  describe ".no_program" do
    it "returns the program of the unscoped faculty-less row" do
      create(:uni_program, faculty: "Engineering", program: "CS")
      create(:uni_program, faculty: "", program: "Undeclared")

      expect(UniProgram.no_program).to eq("Undeclared")
    end

    it "falls back to a fixed label when no faculty-less row exists" do
      create(:uni_program, faculty: "Engineering", program: "CS")

      expect(UniProgram.no_program).to eq("My program is not in the list")
    end
  end

  describe "distinct listings" do
    before do
      create(:uni_program, faculty: "Engineering", department: "Computing", program: "CS")
      create(:uni_program, faculty: "Engineering", department: "Computing", program: "SE")
      create(:uni_program, faculty: "Science", department: "Math", program: "CS")
      create(:uni_program, faculty: "", department: "None", program: "Undeclared")
    end

    it ".unique_programs returns each program once and skips the faculty-less row" do
      expect(UniProgram.unique_programs).to contain_exactly("CS", "SE")
    end

    it ".all_faculties returns each faculty once and skips the empty faculty" do
      expect(UniProgram.all_faculties).to contain_exactly("Engineering", "Science")
    end

    it ".all_departments returns each department once and skips the faculty-less row" do
      expect(UniProgram.all_departments).to contain_exactly("Computing", "Math")
    end
  end

  describe ".programs_by_faculty" do
    it "maps each faculty to its programs" do
      create(:uni_program, faculty: "Engineering", program: "CS")
      create(:uni_program, faculty: "Engineering", program: "SE")
      create(:uni_program, faculty: "Science", program: "Math")
      create(:uni_program, faculty: "", program: "Undeclared")

      # No ORDER BY in the model: compare programs as sets, not ordered arrays.
      expect(UniProgram.programs_by_faculty).to match(
        "Engineering" => contain_exactly("CS", "SE"), "Science" => %w[Math]
      )
    end

    it "collapses a program listed twice (e.g. Bachelor's and PhD) within a faculty" do
      # the table holds one row per level, so the same program repeats;
      # the model dedupes with uniq here but not in the default scope itself.
      create(:uni_program, faculty: "Science", program: "Physics", level: "Bachelor's")
      create(:uni_program, faculty: "Science", program: "Physics", level: "PhD")

      expect(UniProgram.where(program: "Physics").count).to eq(2)
      expect(UniProgram.programs_by_faculty).to eq("Science" => %w[Physics])
    end
  end

  describe "inactive programs" do
    before do
      create(:uni_program, faculty: "Engineering", program: "CS")
      create(:uni_program, faculty: "Engineering", program: "Old Program", active: false)
    end

    it "are active by default" do
      expect(create(:uni_program)).to be_active
    end

    it ".active leaves them out" do
      expect(UniProgram.active.pluck(:program)).to eq(%w[CS])
    end

    it ".programs_by_faculty leaves them out, unless one is the program to keep" do
      expect(UniProgram.programs_by_faculty).to eq("Engineering" => %w[CS])
      expect(UniProgram.programs_by_faculty(keep: "Old Program")).to eq("Engineering" => ["CS", "Old Program"])
    end

    it "still resolve to a department for users who have them" do
      create(:uni_program, faculty: "Engineering", program: "Old Program 2", department: "EECS", active: false)
      user = build(:user, program: "Old Program 2")

      expect(user.department).to eq("EECS")
    end

    it "resolve to the active program's department when both share a name" do
      create(:uni_program, faculty: "Engineering", program: "Shared Name", department: "Retired Dept", active: false)
      create(:uni_program, faculty: "Engineering", program: "Shared Name", level: "Doctorate", department: "Active Dept")

      expect(build(:user, program: "Shared Name").department).to eq("Active Dept")
    end

    it "resolve to the same department every time when all matches are inactive" do
      create(:uni_program, faculty: "Engineering", program: "Gone", department: "Zeta", active: false)
      create(:uni_program, faculty: "Engineering", program: "Gone", level: "Doctorate", department: "Alpha", active: false)

      expect(build(:user, program: "Gone").department).to eq("Alpha")
    end
  end

  describe "uniqueness of active programs" do
    it "refuses a second active row for the same program, level and faculty" do
      create(:uni_program, program: "CS", level: "Master's", faculty: "Engineering")

      expect { create(:uni_program, program: "CS", level: "Master's", faculty: "Engineering", department: "Other") }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows an inactive copy" do
      create(:uni_program, program: "CS", level: "Master's", faculty: "Engineering")

      expect { create(:uni_program, program: "CS", level: "Master's", faculty: "Engineering", active: false) }
        .not_to raise_error
    end
  end
end
