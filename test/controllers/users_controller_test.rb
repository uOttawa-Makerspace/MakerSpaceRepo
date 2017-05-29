require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  ##########
  #create tests
  test "creating the same username or email again return unprocessable_entity" do
    post :create, user: {
                username: "bob",
                name: "Bob",
                email: "fake@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :unprocessable_entity,
                    "How is bob processable when bob is a fixture"
  end

  test "creating a user returns :found and saves user in the database" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
  end

  ##########
  #new tests
  test "new returns :success if user is not signed in and redirects to home if user is" do
    get :new
    assert_response :success or
    assert_redirected_to root_path,
                    "User is signed in but failed at redirecting to home"
  end

  ##########
  #likes tests
  test "should be able to get likes through controller" do
    @user = users(:bob)
    get :likes, username: @user.username
  end

  ##########
  #additional_info tests
  test "should be able to get additional_info" do
    @user = users(:bob)
    get :additional_info, username: @user.username, user: {}
  end

  test "should be able to patch additional_info" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    assert_nil User.find_by(username: "sam").faculty
    patch :additional_info, username: "sam", user: {faculty: "engineering"}
    assert_equal "engineering", User.find_by(username: "sam").faculty
  end

  ##########
  #change_password tests
  test "users should be able to change password" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    @oldpass = @user.password
    post :change_password, username: @user.username,
      user: {old_password: "Password1", password: "Password2", password_confirmation: "Password2"}
    @newpass = User.find_by(username: "sam").password
    assert_equal 'Password changed successfully', flash[:notice]
    assert @oldpass != @newpass
  end

  test "users can't change password if old password is wrong" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    @oldpass = @user.password
    post :change_password, username: @user.username,
      user: {old_password: "WrongOldPass1", password: "Password2", password_confirmation: "Password2"}
    @newpass = User.find_by(username: "sam").password
    assert_equal 'Incorrect old password.', flash.now[:alert]
    assert @oldpass == @newpass
  end

  test "users can't change password if passwords don't match" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    @oldpass = @user.password
    post :change_password, username: @user.username,
      user: {old_password: "Password1", password: "Password2", password_confirmation: "WrongConfirmationPass1"}
    @newpass = User.find_by(username: "sam").password
    assert_nil flash.now[:alert]
    assert @oldpass == @newpass
  end

end
