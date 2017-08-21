require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
    @request.env["HTTP_REFERER"]= staff_index_url
  end

   test "staff succeed at loading Staff Dashboard" do
     get :index

     assert_response :success
   end

   test "regular users are redirected to home" do
     session[:user_id] = users(:bob).id
     session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"

     get :index
     assert_redirected_to root_path
   end

   test "a space is chosen by default" do
     get :index
     assert_response :success
     assert response.body.include? 'welcome to '
   end

   test "a space can be changed" do
     get :index
     assert response.body.include? 'welcome to '

     put :change_space, space_name: 'brunsfield'
     assert_redirected_to staff_dashboard_index_path
     assert_equal flash[:notice], "Space changed successfully"
   end




end
