require 'test_helper'

class Staff::TrainingSessionsControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2025 05:01:41 UTC +00:00"
    @user = User.find_by(username: "olivia")
    @request.env['HTTP_REFERER'] = staff_training_sessions_url
  end

  test "staff can create new training session" do
    post :create_training_session,
      training_session_name: "welding_3",
      training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00")
    assert TrainingSession.where(training_id: Training.find_by(name: "welding_3"),
                                 timeslot: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00"),
                                  user_id: @user.id).present?
    assert_equal flash[:notice], "Training session created succesfully"
    assert_redirected_to staff_training_sessions_url
  end

  test "staff can rename training session by choosing a different training" do
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

  test "staff can reschedule training session by choosing a different timeslot" do
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

end
