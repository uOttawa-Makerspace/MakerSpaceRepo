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
    rfid = rfids(:old)

    assert_no_difference('Rfid.count') do
      post :card_number, rfid: rfid.card_number, mac_address: "m4k3rsp4c3-pi-1"
    end
  end

  test "posting existing card with no user updates updated_at" do
    rfid = rfids(:no_user)
    old_timestamp = rfid.updated_at.to_i

    post :card_number, rfid: rfid.card_number, mac_address: "8runsf13ld-pi-1"

    rfid.reload
    assert_not_equal old_timestamp, rfid.updated_at.to_i
  end

  test "posting existing card with no user returns unprocessable_entity" do
    rfid = rfids(:no_user)

    post :card_number, rfid: rfid.card_number, mac_address: "8runsf13ld-pi-1"

    assert_response :unprocessable_entity
  end

  test "posting existing card with user returns ok" do
    rfid = rfids(:assigned)

    post :card_number, rfid: rfid.card_number, mac_address: "m4k3rsp4c3-pi-1"

    assert_response :ok
  end
end
