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

   test "staff can create training sesssions" do
     post :create_training_session,
        training_session_name: "Lathe"
     assert_redirected_to :back
     assert_equal flash[:notice], "Training session created succesfully"
   end


   test "staff can delete training sessions" do
     patch :delete_training_session, training_session_name: "soldering"
     assert_redirected_to :back
     assert_equal flash[:notice], "Training session deleted succesfully"
   end


   test "staff can't own two sessions with the same name, date, and time" do

   end


   test "staff can add certifications in bulk" do
     @user1 = User.find_by(username: "mary")
     @user2 = User.find_by(username: "bob")
     @user3 = User.find_by(username: "adam")
     post :bulk_add_certifications, bulk_cert_users: [@user1,  @user2, @user3], bulk_certifications: "Lathe"
     assert_redirected_to :back
     assert_equal flash[:notice], "Certifications added succesfully!"
     assert Certification.exists?(user_id: @user1, name: "Lathe", staff_id: @staff.id)
     assert Certification.exists?(user_id: @user2, name: "Lathe", staff_id: @staff.id)
     assert Certification.exists?(user_id: @user3, name: "Lathe", staff_id: @staff.id)
   end



end
