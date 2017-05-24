require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase
   test "regular users are redirected to home" do
     @user = users(:bob)
     get :index
     assert_redirected_to root_path
   end

   test "admins succeed at loading Staff Dashboard" do
     @user = User.create(:username => "test3",
                         :password => "Test12345",
                         :pword => "Test12345",
                         :email => "admin3@test.com",
                         :role => "admin",
                         terms_and_conditions: true)
     get :index
     assert_response :found
   end

end
