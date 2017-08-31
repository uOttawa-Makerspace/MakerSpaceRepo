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
    user = User.create(:name => 'Bobby', :username => 'bob', :email => 'Bobby@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true, :identity => 'community_member', :gender => 'Male')
    assert user.invalid? , "Your username is already in use."

    user = User.create(:name => 'Max', :username => 'max123', :email => 'max@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true, :identity => 'community_member', :gender => 'Male')
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
    user = User.create(:username => 'Bobby123', :name => 'Bobby', :email => 'bob@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true, :identity => 'community_member', :gender => 'Male')
    assert user.invalid? , "Your email is already in use."

    user = User.create(:username => 'max123', :name => 'Max', :email => 'max@gmail.com', :password => 'abcdA34vgh', :terms_and_conditions => true, :identity => 'community_member', :gender => 'Male')
    assert user.valid? , "Your email is already in use."
  end

  test "Terms and Conditions" do
  	user = users(:bob)

  	user.terms_and_conditions = true
  	assert user.terms_and_conditions , "You must agree to the terms and conditions"

    user.terms_and_conditions = false
    refute (user.terms_and_conditions) , "You must agree to the terms and conditions"
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


  test "presence of identity" do
    user = users(:bob)
    assert user.valid?, "Identity is required"

    user.identity = nil
    assert user.invalid?, "Identity is required"
  end

  test "validation of identity" do
    user = users(:bob)
    assert user.valid?, "Your identity is invalid. Must be one of: grad, undergrad, faculty_member, community_member, or unknown"

    user.identity = "unknown"
    assert user.valid?,  "Your identity is invalid. Must be one of: grad, undergrad, faculty_member, community_member, or unknown"

    user.identity = "something invalid"
    assert user.invalid?, "Your identity is invalid. Must be one of: grad, undergrad, faculty_member, community_member"
  end

  test "presence of gender" do
    user = users(:mary)
    assert user.valid?, "Gender is required"

    user.gender = nil
    assert user.invalid?, "Gender is required"
  end

  test "presence of faculty if student" do
    user = users(:bob)
    assert user.valid?, "Please provide your faculty"

    user.faculty = nil
    assert user.invalid?, "Please provide your faculty"

    user = users(:adam)
    user.faculty = nil
    assert user.valid?
  end

  test "presence of program if student" do
    user = users(:bob)
    assert user.valid? , "Please provide your program of study"

    user.program = nil
    assert user.invalid?, "Please provide your program of study"

    user = users(:olivia)
    user.program = nil
    assert user.valid?
  end

  test "presence year of study if student" do
    user = users(:bob)
    assert user.valid?, "Please provide your year_of_study"

    user.year_of_study = nil
    assert user.invalid?, "Please provide your year_of_study"

    user = users(:adam)
    user.year_of_study = nil
    assert user.valid?
  end

  test "presence of student id if student" do
    user = users(:bob)
    assert user.valid?, "Please provide your student id"

    user.student_id = nil
    assert user.invalid?, "Please provide your student id"

    user = users(:olivia)
    user.student_id = nil
    assert user.valid?
  end

  test "length of student_id" do
    user = users(:bob)
    assert user.valid?, "your student id must be 7 characters long"

    user.student_id = 123456
    assert user.invalid?, "your student id must be 7 characters long"
  end


  test "unsigned_tac_users scope catches users with unsigned terms and conditions" do
    assert User.unsigned_tac_users.include? users(:sara)
    assert_equal(users(:sara).terms_and_conditions, false)
  end

  test "valid user" do
    user = users(:john)
    assert user.invalid? , "valid user"

    user.name = "anonymous"
    user.gender = "unknown"
    user.identity = "unknown"

    assert user.valid?, "invalid user"

    user = users(:mary)
    assert user.valid?, "invalid user"
  end

end
