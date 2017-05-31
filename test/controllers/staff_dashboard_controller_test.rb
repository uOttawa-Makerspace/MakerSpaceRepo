require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

   test "admins succeed at loading Staff Dashboard" do
     session[:user_id] = users(:adam).id
     get :index
     assert_response :success
   end

   test "regular users are redirected to home" do
     session[:user_id] = users(:bob).id
     get :index
     assert_redirected_to root_path
   end

end
