require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  ##########
  #create tests
  test "creating the same username or email again return unprocessable_entity" do
    post :create, user: {
                username: "bob",
                name: "Bob",
                email: "fake@fake.fake",
                terms_and_conditions: true,
                password: "Password1"}
    assert_response :unprocessable_entity,
                    "How is bob processable when bob is a fixture"
  end

  test "creating a user returns :found and saves user in the database" do
    post :create, user: {
                username: "sam",
                name: "Sam",
                email: "sam@sam.sam",
                read_and_accepted_waiver_form: true,
                password: "Password1",
                identity: "community_member",
                gender: "Male"}
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
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"
    get :new
    assert_redirected_to root_path, "User is signed in but failed at redirecting to home"
  end

  ##########
  #likes tests
  test "should be able to get likes through controller" do
    get :likes, username: "bob"
    assert_response :found
  end

  ##########
  #update tests
  test "user should be able to update profile with patch" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"
    patch :update, username: "bob", user: {gender: "Female"} #from male
    assert_equal 'Profile updated successfully.', flash[:notice]
    assert_equal "Female", User.find_by(username: "bob").gender
    assert_redirected_to settings_profile_path
  end


  ##########
  #change_password tests
  test "user should be able to change password" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, username: "bob.username",
      user: {old_password: "Password1", password: "Password2", password_confirmation: "Password2"}
    @newpass = User.find_by(username: "bob").password
    assert_equal 'Password changed successfully', flash[:notice]
    assert_not_equal @oldpass, @newpass
    assert_redirected_to settings_admin_path
  end

  test "user can't change password if old password is wrong" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, username: "bob.username",
      user: {old_password: "WrongOldPass1", password: "Password2", password_confirmation: "Password2"}, pword: "Password1"
    @newpass = User.find_by(username: "bob").password
    assert_equal 'Incorrect old password.', flash.now[:alert]
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

  test "user can't change password if passwords don't match" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"
    @oldpass = User.find_by(username: "bob").password
    post :change_password, username: "bob.username",
      user: {old_password: "Password1", password: "Password2", password_confirmation: "WrongConfirmationPass1"}
    @newpass = User.find_by(username: "bob").password
    assert_nil flash.now[:alert]
    assert_equal @oldpass, @newpass
    assert_response :ok
  end

  test "admin can view private repositories on user's profile" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, username: "mary"
    @repo_user = User.find_by username: "mary"
    @repositories = @repo_user.repositories.where(make_id: nil)
    assert @repositories.include?(Repository.find(3))
  end

  test "staff can view private repositories on user's profile" do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, username: "mary"
    @repo_user = User.find_by username: "mary"
    @repositories = @repo_user.repositories.where(make_id: nil)
    assert @repositories.include?(Repository.find(3))
  end

  test "Regular users cannot view private repos of another user" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, username: "mary"
    @repo_user = User.find_by username: "mary"
    @repositories = @repo_user.repositories.public_repos.where(make_id: nil)
    refute @repositories.include?(Repository.find(3))
  end


  test "old valid user should be able to update profile" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, username: "mary", user: {name: "Mary", gender: "Female", identity: "community_member"}
    assert_equal 'Profile updated successfully.', flash[:notice]
    assert_equal "Mary", User.find_by(username: "mary").name
    assert_equal "Female", User.find_by(username: "mary").gender
    assert_equal "community_member", User.find_by(username: "mary").identity
    assert_redirected_to settings_profile_path
  end

  test "Profile cannot be updated if input is invalid" do
    session[:user_id] = User.find_by(username: "john").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, username: "john", user: {name: "John", gender: "Male", identity: "grad"}
    assert_equal "Could not save changes.", flash[:alert]
    assert_redirected_to settings_profile_path
  end

  test "old valid user should be able to update profile with valid inputs" do
    session[:user_id] = User.find_by(username: "john").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, username: "john", user: {name: "John", gender: "Male", identity: "grad", student_id: 9876543, faculty: "arts", program: "Honours BA in English", year_of_study: "3"}
    @user = User.find_by(username: "john")
    assert_equal 'Profile updated successfully.', flash[:notice]
    assert_equal "John", @user.name
    assert_equal "Male", @user.gender
    assert_equal "grad", @user.identity
    assert_equal 9876543, @user.student_id
    assert_equal "arts", @user.faculty
    assert_equal "Honours BA in English", @user.program
    assert_equal "3", @user.year_of_study
    assert_redirected_to settings_profile_path
  end

  
  test "user can view their profile" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    # bob has an invalid repository
    get :show, username: "bob"
    assert_response :success
  end

  test "users can view others' profile" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    # bob has an invalid repository
    get :show, username: "bob"
    assert_response :success
  end

end
