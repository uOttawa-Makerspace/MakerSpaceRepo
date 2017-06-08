require 'test_helper'

class Staff::TrainingSessionsControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @user = User.find_by(username: "olivia")
    @request.env['HTTP_REFERER'] = staff_training_sessions_url
  end

  test "staff can create new training session" do
    post :create_training_session, training_session_name: "welding_3", training_session_time: DateTime.parse("Sat, 02 Jun 2018 02:01:41 UTC +00:00")
    assert_equal flash[:notice], "Training session created succesfully"
    assert_redirected_to staff_training_sessions_url
  end

end
