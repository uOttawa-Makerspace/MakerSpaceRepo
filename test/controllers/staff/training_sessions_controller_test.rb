require 'test_helper'

class Staff::TrainingSessionsControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
    @user = User.find_by(username: "olivia")
    @request.env['HTTP_REFERER'] = staff_training_sessions_url
  end

  test "staff can create a new training session" do
    post :create_training_session,
      training_session_name: "welding_3",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00")
    assert TrainingSession.where(training_id: Training.find_by(name: "welding_3"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id).present?
    assert_equal flash[:notice], "Training session created succesfully"
    assert_redirected_to staff_training_sessions_url
  end

  test "staff can rename a training session by choosing a different training" do
    patch :rename_training_session,
      training_session_name: "lathe_1",
      training_session_new_name: "welding_3",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00")
      assert TrainingSession.where(training_id: Training.find_by(name: "welding_3"),
                                   timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                   user_id: @user.id).present?
      assert !TrainingSession.where(training_id: Training.find_by(name: "lathe_1"),
                                    timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                    user_id: @user.id).present?
      assert_redirected_to (:back)
      assert_equal flash[:notice], "Training session renamed succesfully"
  end

  test "staff can reschedule a training session by choosing a different timeslot" do
    patch :reschedule_training_session,
      training_session_name: "lathe_1",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
      training_session_new_time: DateTime.parse("Sun, 02 Mar 2020 01:01:41 UTC +00:00")
      assert TrainingSession.where(training_id: Training.find_by(name: "lathe_1"),
                                   timeslot: DateTime.parse("Sun, 02 Mar 2020 01:01:41 UTC +00:00"),
                                   user_id: @user.id).present?
      assert !TrainingSession.where(training_id: Training.find_by(name: "lathe_1"),
                                    timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                    user_id: @user.id).present?
      assert_redirected_to (:back)
      assert_equal flash[:notice], "Training session rescheduled succesfully"
  end

  test "staff can delete a training session" do
    delete :delete_training_session,
      training_session_name: "lathe_1",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00")
    assert !TrainingSession.where(training_id: Training.find_by(name: "lathe_1"),
                                  timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id)[0].present?
    assert_redirected_to (:back)
    assert_equal flash[:notice], "Training session deleted succesfully"
  end

  test "staff can add new trainees to exisiting training sessions" do
   post :add_trainees_to_training_session,
     training_session_name: "lathe_1",
     training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
     training_session_new_trainees: [User.find_by(username: "bob")]
   assert_redirected_to :back
   assert_equal flash[:notice], "User successfuly added to the training session"
   @training_session = TrainingSession.where(training_id: Training.find_by(name: "lathe_1"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                 user_id: @user.id)[0]
   assert @training_session.users.include? User.find_by(username: "bob")
   post :add_trainees_to_training_session,
      training_session_name: "lathe_1",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
      training_session_new_trainees: [User.find_by(username: "mary"), User.find_by(username: "bob")]
   assert_redirected_to :back
   assert_equal flash[:alert], "User is already in this training session!"
   assert @training_session.users.include? User.find_by(username: "mary")
  end


  test "staff can certify users in training session" do
    @training_session = training_sessions(:lathe_session)
    @training_session.users << users(:adam)
    @training_session.users << users(:mary)
    @training_session.save
    assert @training_session.users.include? User.find_by(username: "adam")
    assert @training_session.users.include? User.find_by(username: "mary")
    post :certify_trainees,
      training_session_name: Training.find(@training_session.training_id).name,
      training_session_graduates: [User.find_by(username: "mary"), User.find_by(username: "adam")],
      training_session_time: @training_session.timeslot
    assert_equal flash[:notice], "Certified successfuly"
    assert_redirected_to :back
    assert Certification.find_by(user_id: "1337", trainer_id: "777", training: "lathe_1").present?
    assert_equal User.find_by(username: "mary").certifications[0].training, "lathe_1"
  end


end
