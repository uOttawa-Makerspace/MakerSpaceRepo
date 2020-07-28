# require 'rails_helper'
#
# RSpec.describe Admin::UsersController, type: :controller do
#
#   describe "GET /index" do
#
#     context "logged in as regular user" do
#
#       it 'should redirect to root' do
#         user = create(:user, :regular_user)
#         session[:user_id] = user.id
#         session[:expires_at] = Time.zone.now + 10000
#         get :index
#         expect(response).to redirect_to "/"
#       end
#
#     end
#
#     context "logged in as admin" do
#
#       before(:each) do
#         @admin = create(:user, :admin)
#         session[:user_id] = @admin.id
#         session[:expires_at] = Time.zone.now + 10000
#         @space = create(:space)
#         PiReader.create(pi_mac_address: "12:34:56:78:90", pi_location: @space.name)
#         Rfid.create(card_number: "abc", user_id: @admin.id)
#       end
#
#       it 'should get the users in desc order' do
#         get :index
#         expect(response).to have_http_status(:success)
#       end
#
#       it 'should get the users signed in users in all spaces' do
#         LabSession.create(user_id: @admin.id, space_id: @space.id, sign_in_time: 1.hour.ago, sign_out_time: DateTime.now.tomorrow)
#         get :index, params: {p: "signed_in_users"}
#         expect(response).to have_http_status(:success)
#         expect(@controller.instance_variable_get(:@users).count).to eq(1)
#       end
#
#       it 'should get an error (invalid params)' do
#         get :index, params: {p: "abc"}
#         expect(response).to redirect_to admin_users_path
#         expect(flash[:alert]).to eq('Invalid parameters!')
#       end
#
#       it 'should get an error (invalid params)' do
#         get :index, params: {p: "signed_in_users", sort: "abc"}
#         expect(response).to redirect_to admin_users_path
#         expect(flash[:alert]).to eq('Invalid parameters!')
#       end
#
#     end
#
#   end
#
# end
#
#
#
