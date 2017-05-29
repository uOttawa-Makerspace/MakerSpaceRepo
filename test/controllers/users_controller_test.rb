require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  test "creating the same username or email again return unprocessable_entity" do
    #try to create bob again, bob is a fixture
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
    #try to create sam for the first time
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
  end

  test "new returns :success if user is not signed in and redirects to home if user is" do
    get :new
    assert_response :success or
    assert_redirected_to root_path,
                    "User is signed in and failed at redirecting to home"
  end

  test "users should be able sign in to change password" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                terms_and_conditions: true,
                password: "Password1",
                role: "admin"}
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
    @user = User.find_by(username: "sam")
    post :change_password, username: @user.username,
      user: {old_password: "Password1", password: "Password2", password_confirmation: "Password2"}
    assert_equal 'Password changed successfully', flash[:notice]

  end


end
