require 'test_helper'

class RfidControllerTest < ActionController::TestCase

  test "posting without params returns unprocessable_entity" do
    post :card_number

    assert_response :unprocessable_entity
  end

  test "posting new rfid creates new record" do
    assert_difference('Rfid.count', 1) do
      post :card_number, params: { rfid: "completly new" }
    end
  end

  test "posting new rfid returns unprocessable_entity" do
    post :card_number, params: { rfid: "completly new" }

    assert_response :unprocessable_entity
  end

  test "posting existing card does not create a new record" do
    rfid = rfids(:old)

    assert_no_difference('Rfid.count') do
      post :card_number,  params: { rfid: rfid.card_number }
    end
  end

  test "posting existing card with no user updates updated_at" do
    rfid = rfids(:old)
    old_timestamp = rfid.updated_at.to_i

    post :card_number, params: { rfid: rfid.card_number }

    rfid.reload
    assert_not_equal old_timestamp, rfid.updated_at.to_i
  end

  test "posting existing card with no user returns unprocessable_entity" do
    rfid = rfids(:old)

    post :card_number, params: { rfid: rfid.card_number }

    assert_response :unprocessable_entity
  end

  test "posting existing card with user returns ok" do
    rfid = rfids(:assigned)

    post :card_number, params: { rfid: rfid.card_number }

    assert_response :ok
  end
end
