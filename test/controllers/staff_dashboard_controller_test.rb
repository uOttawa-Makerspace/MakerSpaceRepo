require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

   test "admins succeed at loading Staff Dashboard" do
     @user2 = users(:tom)
     get :index
     p "tom is an " + @user2.role
     p request.original_url
     print "\n"
     assert_redirected_to root_path
   end

   test "regular users are redirected to home" do
     @user1 = users(:bob)
     get :index
     p "bob is a " + @user1.role
     p request.original_url
     print "\n"
     assert_response :found
   end

end
