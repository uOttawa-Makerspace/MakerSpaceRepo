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
  test "get new succeeds if user is not signed in" do
    get :new
    assert_response :success
  end

  test "new redirects to home if user is signed in" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    get :new
    assert_redirected_to root_path, "User is signed in but failed at redirecting to home"
  end

  ##########
  #likes tests
  test "should be able to get likes through controller" do
    @user = users(:bob)
    get :likes, username: @user.username
    assert_response :found
  end

  ##########
  #additional_info tests
  test "should be able to get additional_info" do
    @user = users(:bob)
    get :additional_info, username: @user.username, user: {}
    assert_response :found
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
    assert_redirected_to settings_profile_path
  end

  ##########
  #update tests
  test "user should be able to update profile with patch" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    assert_nil User.find_by(username: "sam").location
    patch :update, username: "sam", user: {location: "Ottawa"}
    assert_equal 'Profile updated successfully.', flash[:notice]
    assert_equal "Ottawa", User.find_by(username: "sam").location
    assert_redirected_to settings_profile_path
  end


  ##########
  #change_password tests
  test "user should be able to change password" do
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
    assert_not_equal @oldpass, @newpass
    assert_redirected_to settings_admin_path
  end

  test "user can't change password if old password is wrong" do
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
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

  test "user can't change password if passwords don't match" do
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
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

end
