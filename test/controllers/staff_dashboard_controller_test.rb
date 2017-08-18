require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
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
     assert response.body.include? 'makerspace'
   end

   test "a space can passed in params" do
     get :index, space_name: 'makerspace'

     assert_response :success
     assert response.body.include? 'makerspace'
     refute response.body.include? 'brunsfield'
   end

   test "space doesn't go back to default on its own" do
     get :index, space_name: 'makerspace'
     assert_response :success
     assert response.body.include? 'makerspace'
     refute response.body.include? 'brunsfield'

     get :index
     assert_response :success
     assert response.body.include? 'makerspace'
     refute response.body.include? 'brunsfield'
   end


end
