# frozen_string_literal: true

require 'test_helper'

class Admin::SpacesControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: 'adam').id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'
    @request.env['HTTP_REFERER'] = admin_spaces_url
  end

  test 'admin needs to enter space name in capitale to delete it' do
    space = spaces(:makerspace)

    get :edit, params: { id: space.id }
    delete :destroy, params: { id: space.id, admin_input: 'maKerspaCe', space_id: space.id }
    assert Space.find(space.id).present?

    get :edit, params: { id: space.id }
    delete :destroy, params: { id: space.id, admin_input: 'MAKERSPACE', space_id: space.id }
    assert_not Space.find_by(id: space.id).present?
  end
end
