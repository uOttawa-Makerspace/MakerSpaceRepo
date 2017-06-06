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
        training_session_name: "lathe",
        training_session_time: DateTime.parse("2010-02-11 11:02:57"),
        training_session_course: "GNG2101"
     assert_redirected_to :back
     assert_equal flash[:notice], "Training session created succesfully"
   end


   test "staff can rename training sessions" do
     patch :rename_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57"),
        training_session_new_name: "arduino"
      assert !TrainingSession.where(name: "soldering",
                                    session_time: DateTime.parse("2010-02-11 11:02:57"),
                                    staff_id: "1337").present?
      assert TrainingSession.where(name: "arduino",
                                   session_time: DateTime.parse("2010-02-11 11:02:57"),
                                   staff_id: "1337").present?
      assert_redirected_to :back
      assert_equal flash[:notice], "Training session renamed succesfully"
   end


   test "staff can delete training sessions" do
     delete :delete_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57")
     assert_redirected_to :back
     assert_equal flash[:notice], "Training session deleted succesfully"
     delete :delete_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57")
    assert !TrainingSession.where(name: "soldering",
                                  session_time: DateTime.parse("2010-02-11 11:02:57"),
                                  staff_id: "1337").present?
     assert_redirected_to :back
     assert_equal flash[:alert], "No training session with the given parameters!"
   end


   test "staff can add new trainees to exisiting training sessions" do
     post :add_trainee_to_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57"),
        training_session_new_trainee: User.find_by(username: "bob")
      assert_redirected_to :back
      assert_equal flash[:notice], "User successfuly added to the training session"
      post :add_trainee_to_training_session,
         training_session_name: "soldering",
         training_session_time: DateTime.parse("2010-02-11 11:02:57"),
         training_session_new_trainee: User.find_by(username: "bob")
       assert_redirected_to :back
       assert_equal flash[:alert], "User is already in this training session!"
   end


   test "staff can't own two sessions with the same name, date, and time" do
     post :create_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57")
     assert_redirected_to :back
     assert_equal flash[:alert], "This training session already exists!"
   end


   test "staff can get all users in training session" do
     get :show_all_users_in_training_session,
        training_session_name: "soldering",
        training_session_time: DateTime.parse("2010-02-11 11:02:57")
     assert_response :ok
   end


   test "staff can add certifications in bulk" do
     @user1 = User.find_by(username: "mary")
     @user2 = User.find_by(username: "bob")
     @user3 = User.find_by(username: "adam")
     post :bulk_add_certifications, bulk_cert_users: [@user1,  @user2, @user3], bulk_certifications: "soldering", certification_training_session: training_sessions(:soldering)
     assert_redirected_to :back
     assert_equal flash[:notice], "Certifications added succesfully!"
     assert Certification.exists?(user_id: @user1, name: "soldering", staff_id: @staff.id)
     assert Certification.exists?(user_id: @user2, name: "soldering", staff_id: @staff.id)
     assert Certification.exists?(user_id: @user3, name: "soldering", staff_id: @staff.id)
   end



end
