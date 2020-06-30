require 'rails_helper'

RSpec.describe Printer, type: :model do

  before(:all) do
    create :printer, :UM2P_01
    create :printer, :UM2P_02
    create :printer, :UM3_01
    create :printer, :RPL2_01
    create :printer, :RPL2_02
    create :printer, :dremel_10_17
  end

  describe 'model method' do

    context 'model and number' do
      it 'should return the model and number' do
        expect(Printer.find(1).model_and_number).to eq("Ultimaker 2+; Number UM2P - 01")
      end
    end

    context 'get printer id' do
      it 'should return matching ids' do
        expect(Printer.get_printer_ids("Ultimaker 2+")).to eq([1, 2])
        expect(Printer.get_printer_ids("Ultimaker 3")).to eq([3])
        expect(Printer.get_printer_ids("Replicator 2")).to eq([4, 5])
        expect(Printer.get_printer_ids("Dremel")).to eq([6])
      end
    end

    context 'Get last session' do
      it 'should return last session' do
        create :user, :regular_user
        create :printer_session, :um2p_session
        expect(Printer.get_last_model_session("Ultimaker 2+").printer.number).to eq("UM2P - 02")
      end
    end

    context 'Get last session for printer' do
      it 'should return last session of that specific printer' do
        create :user, :regular_user
        create :printer_session, :um2p_session
        expect(Printer.get_last_number_session(2).printer.number).to eq("UM2P - 02")
      end
    end
  end

end
