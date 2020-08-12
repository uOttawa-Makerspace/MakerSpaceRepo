
require 'rails_helper'

RSpec.describe ProjectKitsController, type: :controller do

  describe "#index" do

    context "index" do

      it 'should show the index page' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'should show redirect the user' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :index
        expect(response).to redirect_to root_path
      end

    end

  end

  describe "#mark_delivered" do

    context "mark_delivered" do

      it 'should show the index page' do
        kit = create(:project_kit)
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :mark_delivered, params: {project_kit_id: kit.id}
        expect(response).to redirect_to project_kits_path
        expect(flash[:notice]).to eq("The kit has been marked as delivered")
        expect(ProjectKit.last.delivered?).to be_truthy
      end

      it 'should show redirect the user' do
        staff = create(:user, :staff)
        session[:user_id] = staff.id
        session[:expires_at] = Time.zone.now + 10000
        get :mark_delivered, params: {project_kit_id: ""}
        expect(response).to redirect_to project_kits_path
        expect(flash[:alert]).to eq("There was an error, try again later")
      end

      it 'should show redirect the user' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :mark_delivered, params: {project_kit_id: ""}
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

    end

  end

end




