require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  #this is unnecessary but feels like it's necessary
  teardown do
    User.where(username: "tom").destroy_all
  end

  test "create doesn't not allow for the same username or email to be inputted again" do
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

  test "new redirect_to home if user is signed in or to new if user is not" do
    get :new
    assert_response :success or
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
  end

  test "should get change_password" do
    get :change_password
    assert_response :success
  end

  test "should get delete" do
    get :delete
    assert_response :success
  end
=end
end
