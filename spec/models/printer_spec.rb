require 'rails_helper'

RSpec.describe Printer, type: :model do

  before(:each) do
    @um2p_1 = create :printer, :UM2P_01
    @um2p_2 = create :printer, :UM2P_02
    @um3 = create :printer, :UM3_01
    @rpl2_1 = create :printer, :RPL2_01
    @rpl2_2 = create :printer, :RPL2_02
    @dremel = create :printer, :dremel_10_17
  end

  describe 'model method' do

    context 'model and number' do
      it 'should return the model and number' do
        expect(@um2p_1.model_and_number).to eq("Ultimaker 2+; Number UM2P - 01")
      end
    end

    context 'get printer id' do
      it 'should return matching ids' do
        expect(Printer.get_printer_ids("Ultimaker 2+")).to eq([@um2p_1.id, @um2p_2.id])
        expect(Printer.get_printer_ids("Ultimaker 3")).to eq([@um3.id])
        expect(Printer.get_printer_ids("Replicator 2")).to eq([@rpl2_1.id, @rpl2_2.id])
        expect(Printer.get_printer_ids("Dremel")).to eq([@dremel.id])
      end
    end

    context 'Get last session' do
      it 'should return last session' do
        create :user, :regular_user
        create(:printer_session, :um2p_session)
        expect(Printer.get_last_model_session("Ultimaker 2+").printer.number).to eq("UM2P - 02")
      end
    end

    context 'Get last session for printer' do
      it 'should return last session of that specific printer' do
        create :user, :regular_user
        create :printer_session, :um2p_session
        expect(Printer.get_last_number_session(Printer.last.id).printer.number).to eq("UM2P - 02")
      end
    end
  end

end
