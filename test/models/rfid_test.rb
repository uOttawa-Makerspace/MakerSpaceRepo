require 'test_helper'

class RfidTest < ActiveSupport::TestCase
  
	test "Card presence" do 
		rfid = rfids(:assigned)

		rfid.card_number = "123456"
		assert rfid.valid? , "Card number is required."

		rfid.card_number = nil
		assert rfid.invalid? , "Card number is required."
	end

	test "Card's uniqueness" do

		rfid = rfids(:assigned)

		rfid.card_number = "123456789"
		assert rfid.invalid?, "Card number is already in use."

		rfid.card_number = "987654321"
		assert rfid.valid?, "Card number is already in use."
	end

end
