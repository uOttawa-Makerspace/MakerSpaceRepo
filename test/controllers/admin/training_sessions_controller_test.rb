# frozen_string_literal: true

require 'test_helper'

class Admin::TrainingSessionsControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: 'adam').id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'
    @request.env['HTTP_REFERER'] = admin_training_sessions_url
  end

  test 'admin can update training session user_id (trainer)' do
    patch :update, params: { id: 1, training_session: { user_id: 1337 } }
    assert_redirected_to @request.env['HTTP_REFERER'] # redirect_to :back
    assert_equal flash[:notice], 'Updated Successfully'
    assert TrainingSession.find_by(id: 1, user_id: 1337).present?
    assert_not TrainingSession.find_by(id: 1, user_id: 777).present?
  end

  test 'admin can destroy training session' do
    delete :destroy, params: { id: 1 }
    assert_redirected_to @request.env['HTTP_REFERER'] # redirect_to :back
    assert_equal flash[:notice], 'Deleted Successfully'
    assert_not TrainingSession.find_by(id: 1).present?
  end
end
