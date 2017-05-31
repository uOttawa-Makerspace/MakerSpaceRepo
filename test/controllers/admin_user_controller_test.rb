require 'test_helper'

class Admin::UsersControllerTest < ActionController::TestCase

  setup do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @request.env['HTTP_REFERER'] = admin_users_url
  end

  test "admin should be able to add certifications in bulk" do
    @user1 = User.find_by(username: "mary")
    @user2 = User.find_by(username: "tom")
    post :bulk_add_certifications, bulk_cert_users: [@user1, @user2], bulk_certifications: "lathe_may_4"
    assert_redirected_to :back
    assert_equal "Certifications added succesfully!", flash[:notice]
  end


end
