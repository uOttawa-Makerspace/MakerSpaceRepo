require 'test_helper'

class SearchControllerTest < ActionController::TestCase

  test "Can search for categories" do
    get :category, params: { slug: 'virtual-reality' }
    assert_response :success
  end

  test "Shows repos with old categorizing (aka single category string column in Repository)" do
    get :category, params: { slug: 'other-projects' }
    assert_response :success
    assert response.body.include? "Repository1"   #3D-Model -> other-projects
    refute response.body.include? "Repository2"
  end

  test "Shows repos with new categorizing (aka Repository has_many Category)" do
    get :category, params: { slug: 'course-related-projects' }
    assert_response :success
    assert response.body.include? "Repository2"   #Course-related Projects -> course-related-projects
    refute response.body.include? "Repository1"
  end

  test "Shows repos with both old and new categorizing" do
    get :category, params: { slug: 'virtual-reality' }
    assert_response :success
    assert response.body.include? "Repository2"
    assert response.body.include? "Repository1"
  end

  test "Shows repos only category option id" do
    get :category, slug: 'course-related-projects'
    assert_response :success
    assert response.body.include? "Repository7"
  end

  test "Shows repos by equipment" do
    get :equipment, params: { slug: '3d-printer' }
    assert_response :success
    assert response.body.include? "Repository1"
    refute response.body.include? "Repository2"
  end

end
