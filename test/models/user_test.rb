require 'test_helper'

class UserTest < ActiveSupport::TestCase
  
  test "Name length" do 
  	user = users(:bob)
  	user.name = "j"*5
  	assert_equal(-1 , (user.name).length <=> 50, "Your name must be less than 50 characters.")

  end

  test "Terms and Conditions" do
  	user = users(:bob)
  	user.terms_and_conditions = true
  	assert true == user.terms_and_conditions ,"You must agree to the terms and conditions"
  end

  test "Allowed characters in the password" do
  	user = users(:bob)
  	user.password = "abABbc246dabc"
  	assert_match(/(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z]).{8,}/, user.password , "Your passwords must have one lowercase letter, one uppercase letter, one number and be eight characters long.")
  end 

  test "Username length" do
  	user = users(:bob)
  	user.username = "A"*19
  	assert_equal(-1 , (user.username).length <=> 20, "Your username must be less than 20 characters.")
  	
  end


end
