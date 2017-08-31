require 'test_helper'

class RfidControllerTest < ActionController::TestCase

  test "posting without params returns unprocessable_entity" do
    post :card_number

    assert_response :unprocessable_entity
  end

  test "posting new rfid creates new record" do
    assert_difference('Rfid.count', 1) do
      post :card_number, rfid: "completly new"
    end
  end

  test "posting new rfid returns unprocessable_entity" do
    post :card_number, rfid: "completly new", mac_address: "m4k3rsp4c3-pi-1"

    assert_response :unprocessable_entity
  end

  test "posting existing card does not create a new record" do
    rfid = rfids(:bobs)

    assert_no_difference('Rfid.count') do
      post :card_number, rfid: rfid.card_number, mac_address: rfid.mac_address
    end
  end

  test "posting existing card with no user updates updated_at" do
    rfid = rfids(:no_user)
    old_timestamp = rfid.updated_at.to_i

    post :card_number, rfid: rfid.card_number, mac_address: rfid.mac_address

    rfid.reload
    assert_not_equal old_timestamp, rfid.updated_at.to_i
  end

  test "posting existing card with no user returns unprocessable_entity" do
    rfid = rfids(:no_user)

    post :card_number, rfid: rfid.card_number, mac_address: rfid.mac_address

    assert_response :unprocessable_entity
  end

  test "posting existing card with user returns ok" do
    rfid = rfids(:marrys)

    post :card_number, rfid: rfid.card_number, mac_address: "m4k3rsp4c3-pi-1"

    assert_response :ok
  end

  test "posting from a newly connected pi creates a new PiReader with no space_id" do
    rfid = rfids(:from_new_pi)

    post :card_number, rfid: rfid.card_number, mac_address: rfid.mac_address

    assert PiReader.find_by(pi_mac_address: rfid.mac_address, space_id: nil).present?
  end

  test "can sign in to a space" do
    rfid = rfids(:marrys)
    raspi =  pi_readers(:two)

    post :card_number, rfid: rfid.card_number, mac_address: raspi.pi_mac_address

    lab_session = LabSession.find_by(user_id: rfid.user_id, space_id: raspi.space.id)
    rfid_status = JSON.parse(response.body)['success']
    
    assert rfid_status == "RFID sign in" #this is what the raspberry pi recieves
    assert lab_session.present?
    assert lab_session.sign_out_time > Time.now
    assert raspi.space.signed_in_users.include? rfid.user
  end

  test "can sign out of a space" do
    rfid = rfids(:adams)
    raspi = pi_readers(:three)

    post :card_number, rfid: rfid.card_number, mac_address: raspi.pi_mac_address

    lab_session = LabSession.where(user_id: rfid.user_id, space_id: raspi.space.id).last
    rfid_status = JSON.parse(response.body)['success']

    assert rfid_status == "RFID sign out" #this is what the raspberry pi recieves
    assert lab_session.present?
    assert lab_session.sign_out_time < Time.now
    refute raspi.space.signed_in_users.include? rfid.user
  end
end
