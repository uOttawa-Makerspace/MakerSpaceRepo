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

    it "raises NoMethodError when no faculty-less row exists" do
      # find_by returns nil and `.program` is called on it unguarded.
      create(:uni_program, faculty: "Engineering", program: "CS")

      expect { UniProgram.no_program }.to raise_error(NoMethodError)
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
end
