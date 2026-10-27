require "rails_helper"

RSpec.describe PiReader, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end
  end

  describe "Methods" do
    context "#pi_mac_with_location" do
      it "should return mac address and location" do
        pi_reader = create(:pi_reader)
        pi_mac_address = pi_reader.pi_mac_address
        pi_location = pi_reader.pi_location
        expect(pi_reader.pi_mac_with_location).to eq(
          "#{pi_mac_address} (#{pi_location})"
        )
      end
    end
  end

  describe "MAC address normalization (A10 review)" do
    it "strips, downcases and turns - into : on create" do
      expect(create(:pi_reader, pi_mac_address: "  AA-BB-CC-DD-EE-FF ").pi_mac_address).to eq("aa:bb:cc:dd:ee:ff")
    end

    it "rejects a duplicate that differs only by case, separator or whitespace" do
      create(:pi_reader, pi_mac_address: "aa:bb:cc:dd:ee:ff")
      ["AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", " Aa:bb:cc:dd:ee:ff"].each do |variant|
        reader = PiReader.new(pi_mac_address: variant)
        expect(reader).not_to be_valid
        expect(reader.errors[:pi_mac_address]).to include("has already been taken")
      end
    end

    it "requires a mac on create" do
      expect(PiReader.new(pi_mac_address: "  ")).not_to be_valid
    end

    describe ".find_by_mac" do
      it "finds a reader whatever the case, separator or padding of the tapped mac" do
        reader = create(:pi_reader, pi_mac_address: "aa:bb:cc:dd:ee:ff")
        ["AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", " aa:bb:cc:dd:ee:ff "].each do |variant|
          expect(PiReader.find_by_mac(variant)).to eq(reader)
        end
      end

      it "finds rows stored before normalization existed (upper-case, hyphenated)" do
        legacy = create(:pi_reader)
        legacy.update_column(:pi_mac_address, "AA-BB-CC-DD-EE-FF")
        expect(PiReader.find_by_mac("aa:bb:cc:dd:ee:ff")).to eq(legacy)
      end

      it "prefers a row with a space over a lower-id legacy space-less variant of the same mac" do
        legacy = create(:pi_reader, space: nil)
        legacy.update_column(:pi_mac_address, "AA:BB:CC:DD:EE:FF")
        registered = create(:pi_reader, pi_mac_address: "x")
        registered.update_column(:pi_mac_address, "aa-bb-cc-dd-ee-ff")
        expect(legacy.id).to be < registered.id
        expect(PiReader.find_by_mac("aa:bb:cc:dd:ee:ff")).to eq(registered)
      end

      it "returns nil for a blank, unknown or non-string mac" do
        create(:pi_reader)
        expect([PiReader.find_by_mac(nil), PiReader.find_by_mac("  "), PiReader.find_by_mac("de:ad:be:ef:00:01"), PiReader.find_by_mac({ a: 1 })]).to all(be_nil)
      end
    end
  end
end
