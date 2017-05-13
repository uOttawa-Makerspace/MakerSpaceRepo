require 'test_helper'

class UsersControllerTest < ActionController::TestCase


  test "create should succeed or ask for input again" do
    post :create, user: {
                username: "bob",
                name: "MyString",
                email: "fake@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :unprocessable_entity
    assert User.exists?(username: "bob")

    post :create, user: {
                username: "toms",
                name: "MyStringToms",
                email: "toms@tom.tom",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :found
    #assert (User.exists?(username: "tom")==true)
  end

=begin
  test "should get new" do
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
