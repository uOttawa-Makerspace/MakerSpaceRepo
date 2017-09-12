require 'test_helper'

class SpaceTest < ActiveSupport::TestCase
  test "User-Space association through LabSession and PiReader" do
    user = users(:sara)
    refute spaces(:brunsfield).users.include? user
    LabSession.create(user_id: user.id, space_id: 2)
    assert spaces(:brunsfield).users.include? user
  end

  test "Sign in" do
    mary_session = lab_sessions(:four)
    # sign_out > Time.zone.now means she's signed in
    assert mary_session.sign_out_time > Time.zone.now
    assert mary_session.space.signed_in_users.include? users(:mary)
  end

  test "Sign out" do
    mary_session = lab_sessions(:two)
    # sign_out < Time.zone.now means she's signed out
    assert mary_session.sign_out_time < Time.zone.now
    refute mary_session.space.signed_in_users.include? users(:mary)
  end

end
