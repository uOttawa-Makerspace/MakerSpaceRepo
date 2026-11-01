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

  # One rule for the identifier a reader is registered with and the one a tap is matched by
  describe ".tap_identifier / identifier bound" do
    it "normalizes and accepts MACs and the short non-MAC identifiers readers in use send" do
      expect(PiReader.tap_identifier(" AA-BB-CC-DD-EE-FF\n")).to eq("aa:bb:cc:dd:ee:ff")
      expect(PiReader.tap_identifier("AB12")).to eq("ab12")
      expect(PiReader.tap_identifier("x")).to eq("x")
      expect(PiReader.tap_identifier("a" * 64)).to eq("a" * 64)
    end

    it "is nil for a missing, non-string, over-long or control-character identifier" do
      [nil, "  ", { a: 1 }, ["aa"], "a" * 65, "aa:bb\tcc", "aa\u0000bb", "ab\u001b12",
       "aa\u202Ebb", "aa\u200Bbb", "aa\u00A0bb", "aa bb", "aa\u2028bb"].each do |bad|
        expect(PiReader.tap_identifier(bad)).to be_nil
      end
    end

    it "rejects registering an identifier that breaks the bound, and accepts one that does not" do
      expect(PiReader.new(pi_mac_address: "a" * 65)).not_to be_valid
      reader = PiReader.new(pi_mac_address: "aa:bb:\tcc")
      expect(reader).not_to be_valid
      expect(reader.errors[:pi_mac_address].join).to include("at most 64 characters", "no spaces, control or invisible characters")
      %W[aa\u202Ebb aa\u200Bbb aa\u00A0bb].push("aa bb").each { |bad| expect(PiReader.new(pi_mac_address: bad)).not_to be_valid }
      expect(PiReader.new(pi_mac_address: "ab12")).to be_valid
      expect(PiReader.new(pi_mac_address: "a" * 64)).to be_valid
    end

    it "rejects writing a bad identifier to an existing row but never re-judges a stored one on another edit" do
      reader = create(:pi_reader)
      reader.pi_mac_address = "a" * 70
      expect(reader).not_to be_valid

      reader = create(:pi_reader)
      reader.update_column(:pi_mac_address, "a" * 70) # a row stored before the bound existed
      reader = PiReader.find(reader.id)
      expect(reader.update(pi_location: "Door")).to be(true)
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

      it "matches legacy rows padded with tabs or newlines like Ruby's strip does" do
        legacy = create(:pi_reader)
        legacy.update_column(:pi_mac_address, "\tAA:BB:CC:DD:EE:FF\n")
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
