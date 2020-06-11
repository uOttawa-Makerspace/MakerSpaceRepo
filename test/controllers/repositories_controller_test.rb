require 'test_helper'

class RepositoriesControllerTest < ActionController::TestCase

  test "users can create a repository" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    post :create, user_username:"mary", slug:"repository44",
    repository: {id: 44,
                title: "Repository44",
                description: "description44",
                category: "3D-Model",
                share_type: "public"}

    assert_response :success, "Failed at creating the repository"
    assert Repository.find_by(title: "Repository44").present?
  end

  test "users can update their repository" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, user_username: "mary", slug: "repository2",
    repository:{description: "mydescription"}
    assert_equal 'mydescription', Repository.find_by(slug: "repository2").description
    assert Repository.find_by(description: "mydescription").present?
    refute Repository.find_by(description: "description2").present?
    assert_equal flash[:notice] , "Project updated successfully!"
  end

  test "Changing share type to private happens successfully" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, user_username: "mary", slug: "repository2",
    repository:{share_type: "private", password: "myPass"}

    assert_equal 'private', Repository.find_by(slug: "repository2").share_type
    assert_equal 'myPass', Repository.find_by(slug: "repository2").password

    assert_equal flash[:notice] , "Project updated successfully!"
  end

  test "Changing share type to public happens successfully" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, user_username: "mary", slug: "repository2",
    repository:{share_type: "public"}

    assert_equal 'public', Repository.find_by(slug: "repository2").share_type
    assert_nil Repository.find_by(slug: "repository2").password

    assert_equal flash[:notice] , "Project updated successfully!"
  end

  test "Changing private to public happens successfully" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    patch :update, user_username: "mary", slug: "repository3",
    repository:{share_type: "public"}

    assert_equal 'public', Repository.find_by(slug: "repository3").share_type
    assert_nil Repository.find_by(slug: "repository3").password

    assert_equal flash[:notice] , "Project updated successfully!"
  end

  test "user can remove repository" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    delete :destroy, user_username: "mary", slug: "repository2",
    repository: {}
    refute Repository.find_by(slug: "repository2").present?
    assert_redirected_to user_path("mary")
  end

  test "unauthorized people will be redirected to password entry page for private repositories" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, user_username: "mary", slug: "repository3"
    assert_redirected_to password_entry_repository_url
  end

  test "admins have access to private repositories" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, user_username: "mary", slug: "repository3"
    assert_response :success
  end

  test "staff have access to private repositories" do
    session[:user_id] = User.find_by(username: "olivia").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, user_username: "mary", slug: "repository3"
    assert_response :success
  end

  test "after entering the password, a regular user can access the private repository" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    post :pass_authenticate, user_username: "mary", slug: "repository3", password: "Password1",
    repository:{password: "Password1", slug:"repository3"}
    assert_equal 'Success', flash[:notice]
    assert_redirected_to repository_path
  end

  test "users can edit their own repository" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :edit, user_username: "bob", slug: "repository1"
    assert_response :success
  end

  test "Admins can edit users' repository" do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :edit, user_username: "bob", slug: "repository1"
    assert_response :success
  end

  test "users cannot edit other users' repositories" do
    session[:user_id] = User.find_by(username: "sara").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :edit, user_username: "mary", slug: "repository2"
    assert_equal "You are not allowed to perform this action!", flash[:alert]
    assert_redirected_to repository_path("mary", "repository2")
  end


  test "repositories without a photo do not break on show" do
    session[:user_id] = User.find_by(username: "mary").id
    session[:expires_at] = "Sat, 03 Jun 2030 05:01:41 UTC +00:00"

    get :show, user_username: "bob", slug: "repository4"
    assert_response :success
  end

end
