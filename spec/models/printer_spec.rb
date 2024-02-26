require "rails_helper"

RSpec.describe Printer, type: :model do
  before(:each) do
    @um2p = create(:printer_type, :UM2P)
    @um3 = create(:printer_type, :UM3)
    @rpl2 = create(:printer_type, :RPL2)
    @dremel = create(:printer_type, :Dremel)

    @um2p_1 = create(:printer, :UM2P_01, printer_type_id: @um2p.id)
    @um2p_2 = create(:printer, :UM2P_02, printer_type_id: @um2p.id)
    @um3_01 = create(:printer, :UM3_01, printer_type_id: @um3.id)
    @rpl2_1 = create(:printer, :RPL2_01, printer_type_id: @rpl2.id)
    @rpl2_2 = create(:printer, :RPL2_02, printer_type_id: @rpl2.id)
    @dremel10_17 = create(:printer, :dremel_10_17, printer_type_id: @dremel.id)
  end

  describe "model method" do
    context "model and number" do
      it "should return the model and number" do
        expect(@um2p_1.model_and_number).to eq(
          "Ultimaker 2+ Test; Number UM2P - 01"
        )
      end
    end

    context "get printer id" do
      it "should return matching ids" do
        expect(Printer.get_printer_ids("Ultimaker 2+ Test")).to eq(
          [@um2p_1.id, @um2p_2.id]
        )
        expect(Printer.get_printer_ids("Ultimaker 3 Test")).to eq([@um3_01.id])
        expect(Printer.get_printer_ids("Replicator 2 Test")).to eq(
          [@rpl2_1.id, @rpl2_2.id]
        )
        expect(Printer.get_printer_ids("Dremel Test")).to eq([@dremel10_17.id])
      end
    end

    context "Get last session" do
      it "should return last session" do
        create :user, :regular_user
        create(:printer_session, printer_id: @um2p_2.id)
        expect(
          Printer.get_last_model_session("Ultimaker 2+ Test").printer.number
        ).to eq("UM2P - 02")
      end
    end

    context "Get last session for printer" do
      it "should return last session of that specific printer" do
        create :user, :regular_user
        create :printer_session, :um2p_session
        expect(
          Printer.get_last_number_session(Printer.last.id).printer.number
        ).to eq("UM2P - 02")
      end
    end
  end
end
