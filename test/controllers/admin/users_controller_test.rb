# # frozen_string_literal: true
#
# require 'test_helper'
#
# class Admin::UsersControllerTest < ActionController::TestCase
#   setup do
#     session[:user_id] = User.find_by(username: 'adam').id
#     session[:expires_at] = 'Sat, 03 Jun 2020 05:01:41 UTC +00:00'
#     # @staff = User.find_by(username: "adam")
#     @request.env['HTTP_REFERER'] = admin_users_url
#   end
#
#   test 'admin can change user role (admin > staff > regular_user)' do
#     patch :set_role, params: { id: users(:mary), role: 'staff' }
#     assert_equal User.find_by(username: 'mary').role, 'staff'
#     assert_redirected_to admin_users_path
#   end
#
#   test 'admin can search for users without filer' do
#     get :search, params: { q: 'mary' }
#     assert response.body.include? 'Mary'
#     assert_not response.body.include? 'Sara'
#   end
#
#   test 'admin can search for users by email' do
#     get :search, params: { q: '@SARA.com', filter: 'Email' }
#     assert response.body.include? 'Sara'
#     assert_not response.body.include? 'Mary'
#   end
#
#   test 'admin can delete a users by email' do
#     delete :delete_user, params: { path: '/123/edit', id: users(:justine) }
#     assert_not User.find_by(username: 'justine').present?
#   end
# end
