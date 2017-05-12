require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  test "should get create" do
    post :create, user: {username: "bob",
                name: "MyString",
                email: "fakke@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response 422
    assert User.exists?(username: "bob")
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
