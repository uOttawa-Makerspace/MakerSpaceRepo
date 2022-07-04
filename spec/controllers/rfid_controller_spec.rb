require 'rails_helper'

RSpec.describe RfidController, type: :controller do
  before :all do
    @user = create(:user, :regular_user)
  end

  before :each do
    session[:user_id] = @user.id
  end

  describe 'POST /card_number' do
    context 'creates rfid' do
      it 'should create an rfid and render json ok' do
        attributes = FactoryBot.attributes_for(:rfid)
        rfid_params = { rfid: attributes[:card_number], mac_address: attributes[:mac_address] }
        expect { post :card_number, params: rfid_params, :format => :json }.to change(Rfid, :count).by(1)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { new_rfid: 'Temporary RFID created' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID' do
        pi_reader = create(:pi_reader)
        attributes = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = { rfid: attributes.card_number, mac_address: attributes.mac_address }
        expect { post :card_number, params: rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign in' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID' do
        pi_reader = create(:pi_reader)
        attributes = create(:rfid, mac_address: pi_reader.pi_mac_address, user: nil)
        rfid_params = { rfid: attributes.card_number, mac_address: attributes.mac_address }
        expect { post :card_number, params: rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { error: 'Temporary RFID already exists' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID and sign out' do
        pi_reader = create(:pi_reader)
        attributes = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = { rfid: attributes.card_number, mac_address: attributes.mac_address }
        expect { post :card_number, params: rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign in' }
        expect(actual).to eq(expected)
        rfid_params = { rfid: attributes.card_number, mac_address: attributes.mac_address }
        expect { post :card_number, params: rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign out' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID at one pi and sign out at other pi' do
        sign_in_pi = create(:pi_reader)
        sign_out_pi = create(:pi_reader, space_id: sign_in_pi.space_id)
        attributes = create(:rfid, mac_address: sign_in_pi.pi_mac_address)
        sign_in_rfid_params = { rfid: attributes.card_number, mac_address: sign_in_pi.pi_mac_address }
        expect { post :card_number, params: sign_in_rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        sign_out_rfid_params = { rfid: attributes.card_number, mac_address: sign_out_pi.pi_mac_address }
        expected = { success: 'RFID sign in' }
        expect(actual).to eq(expected)
        expect { post :card_number, params: sign_out_rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign out' }
        expect(actual).to eq(expected)
      end

      #Temporary RFID Multi-box
      it 'should create an rfid and should sign in rfid ' do
        sign_in_pi = create(:pi_reader)
        sign_out_pi = create(:pi_reader, space_id: sign_in_pi.space_id)
        attributes = FactoryBot.attributes_for(:rfid)
        sign_in_rfid_params = { rfid: attributes[:card_number], mac_address: sign_in_pi.pi_mac_address }
        expect { post :card_number, params: sign_in_rfid_params, :format => :json }.to change(Rfid, :count).by(1)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { new_rfid: 'Temporary RFID created' }
        expect(actual).to eq(expected)
        sign_out_rfid_params = { rfid: attributes[:card_number], mac_address: sign_out_pi.pi_mac_address }
        expect { post :card_number, params: sign_out_rfid_params, :format => :json }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { error: 'Temporary RFID already exists' }
        expect(actual).to eq(expected)
      end
    end
  end
end

