require 'test_helper'

class RepositoriesControllerTest < ActionController::TestCase

  test "can create new repository" do
    session[:user_id] = User.find_by(username: "bob").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    post :create, user_username: 'bob',
                  repository: {title: "some repo", user_id: users(:bob).id},
                  categories: ['Virtual Reality', 'Course-related Projects', 'Mobile Development']
    @repo = Repository.find_by(title: "some repo", user_id: users(:bob).id)
    assert @repo.present?
    assert @repo.categories.include? Category.find_by(category_option_id: CategoryOption.find_by(name: 'Mobile Development'))
  end

end
