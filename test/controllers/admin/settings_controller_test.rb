require 'test_helper'

class Admin::SettingsControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: "adam").id
    session[:expires_at] = "Sat, 03 Jun 2020 05:01:41 UTC +00:00"
    #@staff = User.find_by(username: "adam")
    @request.env['HTTP_REFERER'] = admin_settings_url
  end

end
