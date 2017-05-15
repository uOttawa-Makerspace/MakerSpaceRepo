require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  #this is unnecessary but feels like it's necessary
  teardown do
    User.where(username: "tom").destroy_all
  end

  test "create should succeed or ask for user input again" do
    post :create, user: {
                username: "bob",
                name: "MyString",
                email: "fake@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :unprocessable_entity,
                    "How is bob processable when bob is a fixture"
    assert User.exists?(username: "bob"),
          "\nFailed at reading users.yml \n\tOR \nFailed at finding bob in users.yml"

    post :create, user: {
                username: "tom",
                name: "MyStringTom",
                email: "tom@tom.tom",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found, "\nFailed at creating Tom"
    assert User.exists?(username: "tom"), "\nFailed at saving Tom"
  end
  
=begin
  test "new should " do
    get :new
    assert_response (@new_user = User.new)
  end
=end

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
