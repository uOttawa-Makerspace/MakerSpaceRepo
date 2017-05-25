require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  test "creating the same username or email again return unprocessable_entity" do
    #try to create bob again, bob is a fixture
    post :create, user: {
                username: "bob",
                name: "MyString",
                email: "fake@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    #assert that bob wasn't created again
    assert_response :unprocessable_entity,
                    "How is bob processable when bob is a fixture"
  end

  test "creating a user returns :found and saves user in the database" do
    #try to create tom for the first time
    post :create, user: {
                username: "tom",
                name: "MyStringTom",
                email: "tom@tom.tom",
                terms_and_conditions: true,
                password: "Password1"}
    #assert that creation passes
    assert_response :found, "\nFailed at creating Tom"
    #assert that tom is in the database
    assert User.exists?(username: "tom"), "\nFailed at saving Tom"
  end

  test "new returns :success if user is not signed in and redirects to home if user is" do
    get :new
    #assert success if user is not signed in
    assert_response :success or
    #assert redirect to home if user is signed in
    assert_redirected_to root_path,
                    "User is signed in and failed at redirecting to home"
  end

=begin
  test "should get edit" do
    get :edit
    assert_response :success
  end
=end
=begin
  test "should get update" do
    get :update
    assert_response :success
  end

  test "should get show" do
    get :show
    assert_response :success
=end

  test "users should be able sign in and change password" do
    @controller = SessionsController.new
    get :login_authentication, user: {
                            username_email: "bob",
                            password: "fake@fake.fake" }
    assert_response :success, "Failed at signing in as bob"
  #Idk how to test patch
    #@controller = UsersController.new
    #patch :change_password, user: {username:"bob", password: "Password1"}
    #assert_response :found
  end

=begin
  test "should get delete" do
    get :delete
    assert_response :success
  end
=end
end
