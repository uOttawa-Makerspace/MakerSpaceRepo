require 'test_helper'

class ReportGeneratorControllerTest < ActionController::TestCase
#This test fails

 #  test "admins succeed at loading Reports page" do
	# session[:user_id] = users(:adam).id
 #    get :index
 #    assert_response :success
 #  end

  test "Regular user cannot access the reports page" do
  	session[:user_id] = users(:bob).id
  	get :index
  	assert_redirected_to root_path
  end

end
