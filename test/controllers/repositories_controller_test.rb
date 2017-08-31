require 'test_helper'

class RepositoriesControllerTest < ActionController::TestCase

  test "repositories without a photo do not break on show" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"

    get :show, user_username: "bob", slug: "repository4"
    assert_response :success
  end

end
