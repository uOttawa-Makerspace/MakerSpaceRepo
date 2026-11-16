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

  describe "#resolve!" do
    it "marks the issue inactive and is safe to repeat" do
      issue = create(:printer_issue)
      2.times { issue.resolve! }
      expect(issue.reload.active).to be(false)
    end

    it "raises and keeps the issue active when it is invalid" do
      issue = create(:printer_issue)
      issue.update_columns(summary: "")
      expect { issue.resolve! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(issue.reload.active).to be(true)
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

    it "counts each printer's active issues by the canned summary they contain, else Other" do
      create(:printer_issue, :nozzle_clogged, printer: printer)
      create(:printer_issue, :nozzle_clogged, printer: printer)
      create(:printer_issue, :bed_issue, printer: printer)
      create(:printer_issue, printer: printer, summary: "Something else")
      create(:printer_issue, :extrude_issue, :inactive, printer: printer)
      quiet = create(:printer, :UM3_01)
      create(:printer_issue, :bed_issue, :inactive, printer: quiet)
      expect(Printer.active_issue_counts([quiet, printer]))
        .to eq(printer.id => { "Nozzle clogged" => 2, "Bed issue" => 1, "Other" => 1 })
    end

    it "keys the counts in the order of the printers it is given, in one query" do
      other = create(:printer, :UM3_01)
      create(:printer_issue, printer: printer)
      create(:printer_issue, printer: other)
      counts = nil
      expect(count_queries { counts = Printer.active_issue_counts([other, printer]) }).to eq(1)
      expect(counts.keys).to eq([other.id, printer.id])
    end

    it "leaves out the given issue when counting" do
      create(:printer_issue, :nozzle_clogged, printer: printer)
      left_out = create(:printer_issue, :bed_issue, printer: printer)
      expect(Printer.active_issue_counts([printer], except: left_out.id)).to eq(printer.id => { "Nozzle clogged" => 1 })
    end

    it "groups the loaded active issues the same way without another query" do
      create(:printer_issue, :nozzle_clogged, printer: printer)
      create(:printer_issue, :bed_issue, printer: printer)
      create(:printer_issue, :bed_issue, :inactive, printer: printer)
      create(:printer_issue, printer: printer, summary: "Something else")
      loaded = Printer.includes(:printer_issues).find(printer.id)

      groups = nil
      expect(count_queries { groups = loaded.group_loaded_printer_issues }).to eq(0)
      expect(groups.transform_values(&:size)).to eq("Nozzle clogged" => 1, "Bed issue" => 1, "Other" => 1)
    end
  end
end
