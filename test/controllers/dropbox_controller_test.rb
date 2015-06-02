require 'test_helper'

class DropboxControllerTest < ActionController::TestCase
  test "should get authorize" do
    get :authorize
    assert_response :success
  end

  test "should get unauthorize" do
    get :unauthorize
    assert_response :success
  end

  test "should get callback" do
    get :callback
    assert_response :success
  end

end
