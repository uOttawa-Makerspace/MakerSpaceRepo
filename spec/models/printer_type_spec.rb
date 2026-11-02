require "rails_helper"

RSpec.describe PrinterType, type: :model do
  describe "validations" do
    subject { build(:printer_type, :UM2P) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
  end

  it { should have_many(:printers).dependent(:destroy) }
  it { should have_many(:printer_sessions).through(:printers) }

  describe "scopes" do
    it "splits available from unavailable" do
      on = create(:printer_type, :UM2P)
      off = create(:printer_type, :UM3, available: false)
      expect(PrinterType.available).to include(on)
      expect(PrinterType.available).not_to include(off)
      expect(PrinterType.unavailable).to eq([off])
    end
  end
end
