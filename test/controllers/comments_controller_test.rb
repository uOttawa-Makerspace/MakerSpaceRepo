require 'test_helper'

class CommentsControllerTest < ActionController::TestCase

  test "users can delete their own comments" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    delete :destroy,  params: { id: 1 }
    assert_equal flash[:notice], "Comment deleted succesfully"
  end

  test "admins can delete any comment" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    delete :destroy, params: { id: 1 }
    assert_equal flash[:notice], "Comment deleted succesfully"
  end

  test "users can't delete others' comments" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    delete :destroy, params: { id: 2 }
    assert_equal flash[:alert], "Something went wrong"
  end

end
