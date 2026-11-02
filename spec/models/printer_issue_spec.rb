require "rails_helper"

RSpec.describe PrinterIssue, type: :model do
  describe "associations and validations" do
    it { should belong_to(:printer) }
    it { should belong_to(:reporter).class_name("User") }
    it { should validate_presence_of(:summary) }

    it "allows duplicate active summaries on the same printer (uniqueness is commented out)" do
      printer = create(:printer, :UM2P_01)
      create(:printer_issue, printer: printer, summary: "Nozzle clogged")
      expect(build(:printer_issue, printer: printer, summary: "Nozzle clogged")).to be_valid
    end

    it "does not need a description" do
      expect(build(:printer_issue, description: nil)).to be_valid
    end
  end

  describe ".summaries" do
    it "lists the three canned summaries" do
      expect(PrinterIssue.summaries).to eq(
        nozzle_clogged: "Nozzle clogged", extrude_issue: "Extrude issue", bed_issue: "Bed issue"
      )
    end
  end

  describe "Printer issue helpers" do
    let(:printer) { create(:printer, :UM2P_01) }

    it "limits active_printer_issues to active ones" do
      active = create(:printer_issue, printer: printer)
      create(:printer_issue, :inactive, printer: printer)
      expect(printer.active_printer_issues).to eq([active])
    end

    it "groups active issues by the canned summary they contain, else Other" do
      create(:printer_issue, :nozzle_clogged, printer: printer)
      create(:printer_issue, :nozzle_clogged, printer: printer)
      create(:printer_issue, :bed_issue, printer: printer)
      create(:printer_issue, printer: printer, summary: "Something else")
      create(:printer_issue, :extrude_issue, :inactive, printer: printer)
      expect(printer.count_printer_issues).to eq("Nozzle clogged" => 2, "Bed issue" => 1, "Other" => 1)
    end
  end
end
