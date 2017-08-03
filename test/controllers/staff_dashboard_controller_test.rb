require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

   test "staff succeed at loading Staff Dashboard" do
     session[:user_id] = users(:olivia).id
     session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
     get :index
     assert_response :success
   end

   test "regular users are redirected to home" do
     session[:user_id] = users(:bob).id
     session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
     get :index
     assert_redirected_to root_path
   end

end
