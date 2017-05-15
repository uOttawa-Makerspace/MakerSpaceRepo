require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  test "create doesn't allow for the same username or email to be inputted again" do
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

  test "create works and saves user in the database" do
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

  test "new reditects to home if user is signed in or to new if user is not" do
    get :new
    #assert success if user is not signed in
    assert_response :success or
    #assert redirect to home if user is signed in
    assert_redirected_to root_path
  end

=begin
  test "should get edit" do
    get :edit
    assert_response :success
  end

  test "should get update" do
    get :update
    assert_response :success
  end

  test "should get show" do
    get :show
    assert_response :success
=end

  test "should be able to change password" do
    @controller = SessionsController.new
    get :login_authentication, user: {
                            username_email: "bob",
                            password: "fake@fake.fake" }
    assert_response :success, "Failed at signing in as bob"
  #Idk how to test patch
    #@controller = UsersController.new
    #@bob = users(:bob)
    #patch :change_password, @bob
  end

=begin
  test "should get delete" do
    get :delete
    assert_response :success
  end
=end
end
