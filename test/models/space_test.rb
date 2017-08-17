require 'test_helper'

class SpaceTest < ActiveSupport::TestCase
  test "User->LabSession->PiReader->Space association" do
    user = users(:sara)

    refute spaces(:brunsfield).users.include? user

    LabSession.create(user_id: user.id, pi_reader_id: 2)
    assert spaces(:brunsfield).users.include? user
  end

  test "Sign in" do
    mary_session = lab_sessions(:four)

    assert mary_session.sign_out_time > Time.now # sign_out > Time.now means she's signed in
    assert mary_session.space.signed_in_users.include? users(:mary)
  end

  test "Sign out" do
    mary_session = lab_sessions(:two)

    assert mary_session.sign_out_time < Time.now # sign_out < Time.now means she's signed out
    refute mary_session.space.signed_in_users.include? users(:mary)
  end

end
