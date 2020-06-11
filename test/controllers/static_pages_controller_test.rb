# frozen_string_literal: true

require 'test_helper'

class StaticPagesControllerTest < ActionController::TestCase
  test 'should get home' do
    get :home
    assert_response :success
  end

  test 'Old and invalid users cannot reset their password' do
    get :reset_password, params: { email: 'john@gmail.com' }
    assert_equal 'Something went wrong, try again.', flash[:alert]
    assert_redirected_to forgot_password_path
  end

  test 'Old but valid users can reset their password' do
    get :reset_password, params: { email: 'mary@gmail.com' }
    assert_equal 'Check your email for your new password.', flash[:notice]
    assert_redirected_to root_path
  end
end
