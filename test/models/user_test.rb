require 'test_helper'

class UserTest < ActiveSupport::TestCase
  
  test "Name length" do 
  	user = users(:bob)

  	user.name = "j"*5
  	assert user.valid? , "Your name must be less than 50 characters."

    user.name = "j"*51
    assert user.invalid? , "Your name must be less than 50 characters."

  end

  test "Presence of Username" do
    user = users(:bob)

    user.username = "bob"
    assert user.valid? , "Your username is required."

    user.username = nil
    assert user.invalid? , "Your username is required."
  end

  test "Username length" do
    user = users(:bob)

    user.username = "A"*10
    assert user.valid? , "Your username must be less than 20 characters."

    user.username = "A"*21
    assert user.invalid? , "Your username must be less than 20 characters."
  end

  test "Uniqueness of username" do
    user = User.create(:name => 'Bobby', :username => 'bob', :email => 'Bobby@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true)
    assert user.invalid? , "Your username is already in use."

    user = User.create(:name => 'Max', :username => 'max123', :email => 'max@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true)
    assert user.valid? , "Your username is already in use."
  end


  test "Presence of Email" do
    user = users(:bob)

    user.email = "bob@gmail.com"
    assert user.valid? , "Your email is required."

    user.email = nil
    assert user.invalid? , "Your email is required."
  end

  test "Uniqueness of email" do
    user = User.create(:username => 'Bobby123', :name => 'Bobby', :email => 'bob@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true)
    assert user.invalid? , "Your email is already in use."

    user = User.create(:username => 'max123', :name => 'Max', :email => 'max@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true)
    assert user.valid? , "Your email is already in use."
  end

  test "Terms and Conditions" do
  	user = users(:bob)

  	user.terms_and_conditions = true
  	assert user.terms_and_conditions , "You must agree to the terms and conditions"

    user.terms_and_conditions = false
    assert !(user.terms_and_conditions) , "You must agree to the terms and conditions"
  end

  test "Allowed characters in the password" do
  	user = users(:bob)

  	user.password = "abABbc246dabc"
    assert user.valid? ,"Your passwords must have one lowercase letter, one uppercase letter, one number and be eight characters long."
  
    user.password = "abcd"
    assert user.invalid? ,"Your passwords must have one lowercase letter, one uppercase letter, one number and be eight characters long."
  end   

  test "Presence of password" do
      user = users(:bob)

      user.password = "abABbc246dabc"
      assert user.valid? , "Your password is required."
      
      user.password = nil
      assert user.invalid? , "Your password is required."
  end

  test "Passwords matching" do
    user = User.create(:password => 'abABbc246dabc', :password_confirmation => 'abABbc246dabc')
    assert_equal( user.password, user.password_confirmation, "Your passwords do not match.")
    
    user = User.create(:password => 'abABbc246dabc', :password_confirmation => 'ABabBC135DABC')
    assert_not_equal( user.password, user.password_confirmation, "Your passwords do not match.")
  end

end
