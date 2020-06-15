# frozen_string_literal: true

require 'test_helper'

class Admin::SettingsControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: 'adam').id
    session[:expires_at] = 'Sat, 03 Jun 2020 05:01:41 UTC +00:00'
    # @staff = User.find_by(username: "adam")
    @request.env['HTTP_REFERER'] = admin_settings_url
  end

  test 'admin can pin/unpin a repository' do
    assert_not Repository.first.featured?
    get :pin_unpin_repository, params: { repository_id: 1 }
    assert Repository.first.featured?

    assert Repository.second.featured?
    get :pin_unpin_repository, params: { repository_id: 2 }
    assert_not Repository.second.featured?
  end
end
