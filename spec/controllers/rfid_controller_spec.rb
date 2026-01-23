require 'rails_helper'

RSpec.describe RfidController, type: :controller do
  # Essential for testing sidekiq/active_job logic with queue_adapter = :test
  include ActiveJob::TestHelper 

  before :all do
    @user = create(:user, :regular_user)
    # Reuse this tier to prevent creating it multiple times
    @tier = create(
      :membership_tier,
      title_en: 'Faculty membership',
      title_fr: 'Adhésion de la faculté',
      internal_price: 0,
      external_price: 0,
      duration: 4.months.to_i
    )
  end

  before :each do
    session[:user_id] = @user.id
  end

  describe 'POST /card_number' do
    context 'creates rfid' do
      # PERFORMANCE FIX: 
      # Previously, every test created a new pi_reader, which created a new Space (0.6s).
      # Now we create it once per example using 'let', saving ~5 seconds in this block.
      let(:pi_reader) { create(:pi_reader) }
      let(:rfid_attributes) { FactoryBot.attributes_for(:rfid) }

      it 'should create an rfid and render json ok' do
        rfid_params = {
          rfid: rfid_attributes[:card_number],
          mac_address: pi_reader.pi_mac_address
        }
        expect {
          post :card_number, params: rfid_params, format: :json
        }.to change(Rfid, :count).by(1)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { new_rfid: 'Temporary RFID created' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID' do
        existing_rfid = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = {
          rfid: existing_rfid.card_number,
          mac_address: existing_rfid.mac_address
        }
        expect {
          post :card_number, params: rfid_params, format: :json
        }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign in' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID with Space ID' do
        existing_rfid = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = {
          rfid: existing_rfid.card_number,
          space_id: pi_reader.space_id
        }
        expect {
          post :card_number, params: rfid_params, format: :json
        }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { success: 'RFID sign in' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should MOT sign in RFID without Mac Address or Space ID' do
        existing_rfid = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = { rfid: existing_rfid.card_number }
        expect {
          post :card_number, params: rfid_params, format: :json
        }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { new_rfid: 'Error, missing space_id or mac_address param' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID (already exists check)' do
        # Note: creates a new RFID but no user attached
        existing_rfid = create(:rfid, mac_address: pi_reader.pi_mac_address, user: nil)
        rfid_params = {
          rfid: existing_rfid.card_number,
          mac_address: existing_rfid.mac_address
        }
        expect {
          post :card_number, params: rfid_params, format: :json
        }.to change(Rfid, :count).by(0)
        actual = JSON.parse(response.body, symbolize_names: true)
        expected = { error: 'Temporary RFID already exists' }
        expect(actual).to eq(expected)
      end

      it 'should not create rfid and should sign in RFID and sign out' do
        existing_rfid = create(:rfid, mac_address: pi_reader.pi_mac_address)
        rfid_params = {
          rfid: existing_rfid.card_number,
          mac_address: existing_rfid.mac_address
        }
        
        # Sign In
        post :card_number, params: rfid_params, format: :json
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ success: 'RFID sign in' })
        
        # Sign Out
        post :card_number, params: rfid_params, format: :json
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ success: 'RFID sign out' })
      end

      it 'should not create rfid and should sign in RFID at one pi and sign out at other pi' do
        # Note: Use the 'pi_reader' let for the first one, create a second one on same space
        sign_in_pi = pi_reader 
        sign_out_pi = create(:pi_reader, space: sign_in_pi.space) # Reuse Space!
        
        existing_rfid = create(:rfid, mac_address: sign_in_pi.pi_mac_address)
        
        sign_in_rfid_params = {
          rfid: existing_rfid.card_number,
          mac_address: sign_in_pi.pi_mac_address
        }
        
        post :card_number, params: sign_in_rfid_params, format: :json
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ success: 'RFID sign in' })
        
        sign_out_rfid_params = {
          rfid: existing_rfid.card_number,
          mac_address: sign_out_pi.pi_mac_address
        }
        
        post :card_number, params: sign_out_rfid_params, format: :json
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ success: 'RFID sign out' })
      end

      # Temporary RFID Multi-box
      it 'should create an rfid and should sign in rfid ' do
        sign_in_pi = pi_reader
        sign_out_pi = create(:pi_reader, space: sign_in_pi.space) # Reuse Space!
        
        sign_in_rfid_params = {
          rfid: rfid_attributes[:card_number],
          mac_address: sign_in_pi.pi_mac_address
        }
        
        expect {
          post :card_number, params: sign_in_rfid_params, format: :json
        }.to change(Rfid, :count).by(1)
        
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ new_rfid: 'Temporary RFID created' })
        
        sign_out_rfid_params = {
          rfid: rfid_attributes[:card_number],
          mac_address: sign_out_pi.pi_mac_address
        }
        
        expect {
          post :card_number, params: sign_out_rfid_params, format: :json
        }.to change(Rfid, :count).by(0)
        
        expect(JSON.parse(response.body, symbolize_names: true)).to eq({ error: 'Temporary RFID already exists' })
      end
    end

    context 'creates memberships' do
      before :all do
        # Be careful with before:all, ensure cleanup if not using transactional fixtures
        @pi_reader = create(:pi_reader) 
      end

      it 'should create a faculty membership for an engineering student' do
        @rfid = create(:rfid, mac_address: @pi_reader.pi_mac_address, user: create(:user, :student))
        @rfid_params = {
          rfid: @rfid[:card_number],
          mac_address: @rfid[:mac_address]
        }
        user = @rfid.user
        
        # "Grant Membership" job runs immediately.
        expect {
          perform_enqueued_jobs { post :card_number, params: @rfid_params }
        }.to change { user.reload.active_membership }.to be_present
      end

      it 'should not create a membership for non-engineering students' do
        @rfid = create(:rfid, mac_address: @pi_reader.pi_mac_address, user: create(:user, :student, :non_engineering))
        @rfid_params = {
          rfid: @rfid[:card_number],
          mac_address: @rfid[:mac_address]
        }
        user = @rfid.user
        
        # Even though we expect nothing, we should run jobs to be sure
        perform_enqueued_jobs { post :card_number, params: @rfid_params }
        
        expect(user.reload.active_membership).to be_blank
      end

      it "should revoke membership for students if they're no longer eligible" do
        @rfid = create(:rfid, mac_address: @pi_reader.pi_mac_address, user: create(:user, :student))
        @rfid_params = {
          rfid: @rfid[:card_number],
          mac_address: @rfid[:mac_address]
        }
        user = @rfid.user

        # 1. Sign In (Grant Membership)
        # Must perform jobs to actually create the membership
        perform_enqueued_jobs do
          post :card_number, params: @rfid_params
        end
        expect(user.reload.has_active_membership?).to be true

        # 2. Make User Ineligible
        user.update(faculty: 'Social Sciences')

        # 3. Sign Out
        # Usually doesn't trigger complex logic, but good to be consistent
        post :card_number, params: @rfid_params
        expect(response).to have_http_status :success

        # 4. Sign In Again (Revoke Membership)
        # This triggers the "Check Eligibility" job which should now FAIL
        # and consequently revoke the membership.
        perform_enqueued_jobs do
          post :card_number, params: @rfid_params
        end
        
        expect(response).to have_http_status :success
        expect(user.reload.has_active_membership?).to be false
      end
    end
  end
end