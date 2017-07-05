require 'test_helper'

class SearchControllerTest < ActionController::TestCase

  test "can search for categories" do
    get :category, slug: 'virtual-reality'
    assert_response :success
  end

end
