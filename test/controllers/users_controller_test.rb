require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  ##########
  #create tests
  test "creating the same username or email again return unprocessable_entity" do
    post :create, params: { user: {
                            username: "bob",
                            name: "Bob",
                            email: "fake@fake.fake",
                            terms_and_conditions: true,
                            password: "Password1"} }
    assert_response :unprocessable_entity,
                    "How is bob processable when bob is a fixture"
  end

  test "creating a user returns :found and saves user in the database" do
    post :create, params: { user: {
                            username: "sam",
                            name: "Sam",
                            email: "sam@sam.sam",
                            terms_and_conditions: true,
                            password: "Password1",
                            identity: "community_member",
                            gender: "Male"} }
    assert_response :found, "\nFailed at creating Sam"
    assert User.exists?(username: "sam"), "\nFailed at saving Sam"
  end

  ##########
  #new tests
  test "get new succeeds if user is not signed in" do
    get :new
    assert_response :success
  end

  test "new redirects to home if user is signed in" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    get :new
    assert_redirected_to root_path, "User is signed in but failed at redirecting to home"
  end

  ##########
  #likes tests
  test "should be able to get likes through controller" do
    get :likes, params: {username: "bob"}
    assert_response :found
  end

  ##########
  #update tests
  test "user should be able to update profile with patch" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    patch :update, params: { username: "bob", user: {gender: "female"} }
    assert_equal 'Profile updated successfully.', flash[:notice]
    assert_equal "female", User.find_by(username: "bob").gender
    assert_redirected_to settings_profile_path
  end


  ##########
  #change_password tests
  test "user should be able to change password" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, params: { username: "bob.username",
                                     user: {old_password: "Password1", password: "Password2", password_confirmation: "Password2"} }
    @newpass = User.find_by(username: "bob").password
    assert_equal 'Password changed successfully', flash[:notice]
    assert_not_equal @oldpass, @newpass
    assert_redirected_to settings_admin_path
  end

  test "user can't change password if old password is wrong" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, params: { username: "bob.username",
                                    user: {old_password: "WrongOldPass1", password: "Password2", password_confirmation: "Password2"},
                                    pword: "Password1" }
    @newpass = User.find_by(username: "bob").password
    assert_equal 'Incorrect old password.', flash.now[:alert]
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

  test "user can't change password if passwords don't match" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, params: { username: "bob.username",
                                      user: {old_password: "Password1", password: "Password2", password_confirmation: "WrongConfirmationPass1"} }
    @newpass = User.find_by(username: "bob").password
    assert_nil flash.now[:alert]
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

end
