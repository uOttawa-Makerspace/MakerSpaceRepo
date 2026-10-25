require "rails_helper"

# Chunk 15: extra Printer pins (validations, ordering, naming) on top of printer_spec.rb.
RSpec.describe Printer, type: :model do
  describe "validations" do
    it "requires a number" do
      expect(build(:printer, :UM2P_01, number: "")).not_to be_valid
    end

    it "scopes number uniqueness to the printer type" do
      create(:printer, :UM2P_01)
      expect(build(:printer, :UM2P_01)).not_to be_valid
      expect(build(:printer, :UM3_01)).to be_valid
    end

    it "does not require a printer type" do
      expect(Printer.new(number: "1")).to be_valid
    end
  end

  describe "default ordering" do
    it "orders by type, then number length, then lower(number)" do
      type = create(:printer_type, :UM2P)
      %w[10 2 1 b A].each { |n| Printer.create!(number: n, printer_type: type) }
      expect(Printer.where(printer_type: type).pluck(:number)).to eq(%w[1 2 A b 10])
    end
  end

  describe "#name" do
    it "is short_form - number" do
      expect(create(:printer, :UM2P_01).name).to eq("UM2P - 01")
    end

    it "keeps the dash with a blank short form" do
      expect(create(:printer, :dremel_10_17).name).to eq(" - 17")
    end

    it "does not fail without a type" do
      expect(Printer.new(number: "3").name).to eq(" - 3")
    end
  end

  describe "#model_and_number" do
    # WART(D-EQ27): model_and_number raises NoMethodError for a printer without a printer type (the association is optional)
    it "raises for an orphan printer" do
      expect { Printer.new(number: "3").model_and_number }.to raise_error(NoMethodError)
    end
  end

  describe "associations" do
    it "destroys its sessions" do
      printer = create(:printer, :UM2P_01)
      create(:printer_session, printer: printer)
      expect { printer.destroy }.to change(PrinterSession, :count).by(-1)
    end

    # WART(D-EQ29): printer_issues has no dependent option, so destroying a printer that ever had an issue raises InvalidForeignKey
    it "cannot be destroyed once it has printer issues" do
      printer = create(:printer, :UM2P_01)
      create(:printer_issue, printer: printer)
      expect { printer.destroy }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
