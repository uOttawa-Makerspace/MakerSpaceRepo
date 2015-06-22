require 'test_helper'

class SettingsControllerTest < ActionController::TestCase
  test "should get profile" do
    get :profile
    assert_response :success
  end

  test "should get admin" do
    get :admin
    assert_response :success
  end

end
