require 'test_helper'

class Staff::TrainingSessionsControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
    @user = User.find_by(username: "olivia")
    @request.env['HTTP_REFERER'] = staff_training_sessions_url
  end


  test "staff can initiate a new training_session" do
    get :new
    assert_response :ok
  end


  test "staff can create a new training session" do
  post :create, training_session_users: [users(:bob).id, users(:mary).id], training_id: Training.last.id, course: "GNG2205"
  @new_training_session = TrainingSession.where(training_id: Training.last.id, user_id: @user.id, course: "GNG2205").last
  assert @new_training_session.present?
  assert @new_training_session.users.include? User.find_by(username: "bob")
  assert_redirected_to staff_training_session_path(@new_training_session.id)
  end


  test "staff can change the trainging type by choosing a different training" do
    patch :update, params: {
      id: training_sessions(:lathe_1_session),
      changed_params: {training_id: trainings(:welding_3)} }
    assert TrainingSession.find_by(training_id: Training.find_by(name: "welding_3"),
                                 user_id: @user.id).present?
    refute TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  user_id: @user.id).present?
    assert_redirected_to staff_training_sessions_url
    assert_equal flash[:notice], "Training session updated succesfully"
  end


  test "staff can certify users in training session" do
    training_session = training_sessions(:lathe_1_session)
    training_session.users << User.find_by(username: "adam")
    training_session.save
    assert training_session.users.include? User.find_by(username: "adam")
    post :certify_trainees, params: { id: training_session }
    assert_redirected_to new_staff_training_session_path
    assert Certification.find_by(user_id: users(:adam).id, training_session_id: training_sessions(:lathe_1_session).id).present?
  end


  test "staff can't delete a training session (only admins can)" do
    delete :destroy, params: { id: training_sessions(:lathe_1_session) }
    assert TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  user_id: @user.id).present?
    assert_redirected_to staff_training_sessions_url
    assert_equal flash[:alert], "Something went wrong or you're not an admin"
  end

  test "admins can delete a training session" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
    delete :destroy, params: { id: training_sessions(:lathe_1_session) }
    refute TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  user_id: @user.id).present?
    assert_redirected_to new_staff_training_session_path
    assert_equal flash[:notice], "Training session deleted succesfully"
  end

end
