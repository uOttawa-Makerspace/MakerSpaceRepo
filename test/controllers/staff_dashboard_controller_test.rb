require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @staff = User.find_by(username: "olivia")
    @request.env['HTTP_REFERER'] = staff_dashboard_index_url
  end

   test "admins succeed at loading Staff Dashboard" do
     get :index
     assert_response :success
   end

   test "regular users are redirected to home" do
     session[:user_id] = users(:bob).id
     session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
     get :index
     assert_redirected_to root_path
   end

   test "staff can add certifications in bulk" do
     @user1 = User.find_by(username: "mary")
     @user2 = User.find_by(username: "bob")
     @user3 = User.find_by(username: "adam")
     post :bulk_add_certifications, bulk_cert_users: [@user1,  @user2, @user3], bulk_certifications: "Lathe"
     assert_redirected_to :back
     assert_equal flash[:notice], "Certifications added succesfully!"
     assert Certification.exists?(user_id: @user1, name: "Lathe", staff_id: @staff)
     assert Certification.exists?(user_id: @user2, name: "Lathe", staff_id: @staff)
     assert Certification.exists?(user_id: @user3, name: "Lathe", staff_id: @staff)

   end

end
