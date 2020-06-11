# frozen_string_literal: true

require 'test_helper'

class StaffDashboardControllerTest < ActionController::TestCase
  setup do
    session[:user_id] = User.find_by(username: 'adam').id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'
    @request.env['HTTP_REFERER'] = staff_index_url
  end

  test 'staff succeed at loading Staff Dashboard' do
    get :index

    assert_response :success
  end

  test 'regular users are redirected to home' do
    session[:user_id] = users(:bob).id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'

    get :index
    assert_redirected_to root_path
  end

  test 'a space is chosen by default' do
    get :index
    assert_response :success
    assert response.body.include? 'Welcome to '
  end

  test 'a space can be changed' do
    get :index
    assert response.body.include? 'Welcome to '

    put :change_space, params: { space_name: 'Brunsfield Centre' }
    assert_redirected_to :back
    assert_equal flash[:notice], 'Space changed successfully'
  end

  test 'staff can link rfid to a user' do
    session[:user_id] = users(:olivia).id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'
    @request.env['HTTP_REFERER'] = user_url(users(:sara))
    rfid = rfids(:no_user)
    put :link_rfid, params: { card_number: rfid.card_number, user_id: users(:sara) }
    assert_redirected_to :back
    assert users(:sara).rfid.present?
  end

  test 'staff can unlink rfid from a user' do
    session[:user_id] = users(:olivia).id
    session[:expires_at] = 'Sat, 03 Jun 2025 05:01:41 UTC +00:00'
    @request.env['HTTP_REFERER'] = user_url(users(:sara))
    rfid = rfids(:marys)
    put :unlink_rfid, params: { card_number: rfid.card_number }
    assert_redirected_to :back
    assert_not users(:mary).rfid.present?
  end

  test 'staff can sign out everyone at once' do
    user = users(:sara)
    space = spaces(:brunsfield)
    LabSession.create(user_id: user.id, space_id: space.id)
    get :sign_out_all_users, params: { space: space }
    assert_empty space.signed_in_users
  end
end
