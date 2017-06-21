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
    post :create, training_session: {
      training_id: "2",
      timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
      user_id: @user.id
    }, training_session_users: users(:bob, :mary)
    @training_session = TrainingSession.find_by(training_id: Training.find_by(name: "welding_3"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                 user_id: @user.id)
    assert @training_session.present?
    assert_equal flash[:notice], "Training session created succesfully"
    assert_response :ok
  end


  test "staff can change the trainging type by choosing a different training" do
    patch :update,
      id: training_sessions(:lathe_session),
      training_session_new_training_id: trainings(:welding_3)
    assert TrainingSession.find_by(training_id: Training.find_by(name: "welding_3"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                 user_id: @user.id).present?
    refute TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id).present?
    assert_redirected_to (:back)
    assert_equal flash[:notice], "Training session updated succesfully"
  end


  test "staff can reschedule a training session by choosing a different timeslot" do
    patch :update,
      id: training_sessions(:lathe_session),
      training_session_new_time: DateTime.parse("Sun, 02 Mar 2020 01:01:41 UTC +00:00")
    assert TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                 timeslot: DateTime.parse("Sun, 02 Mar 2020 01:01:41 UTC +00:00"),
                                 user_id: @user.id).present?
    refute TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id).present?
    assert_redirected_to (:back)
    assert_equal flash[:notice], "Training session updated succesfully"
  end


  test "staff can add new trainees to exisiting training sessions" do
   patch :update,
    id: training_sessions(:lathe_session),
    training_session_new_trainees: users(:bob, :mary)
   assert_redirected_to :back
   training_session = TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                 user_id: @user.id)
   assert training_session.users.include? User.find_by(username: "bob")
   assert training_session.users.include? User.find_by(username: "mary")
   assert_equal flash[:notice], "Training session updated succesfully"
   assert_redirected_to :back
  end


  test "staff can certify users in training session" do
    training_session = training_sessions(:lathe_session)
    training_session.users << User.find_by(username: "adam")
    training_session.users << User.find_by(username: "mary")
    training_session.save
    assert training_session.users.include? User.find_by(username: "adam")
    assert training_session.users.include? User.find_by(username: "mary")
    post :certify_trainees,
      id: training_session,
      training_session_graduates: [User.find_by(username: "mary"), User.find_by(username: "adam")]
    assert_equal flash[:notice], "Users certified successfuly"
    assert_redirected_to :back
    assert Certification.find_by(user_id: "1337", trainer_id: "777", training: "lathe_1").present?
  end


  test "staff can delete a training session" do
    delete :delete_training_session,
      id: training_sessions(:lathe_session)
    refute TrainingSession.find_by(training_id: Training.find_by(name: "lathe_1"),
                                  timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id).present?
    assert_redirected_to (:back)
    assert_equal flash[:notice], "Training session deleted succesfully"
  end
end
