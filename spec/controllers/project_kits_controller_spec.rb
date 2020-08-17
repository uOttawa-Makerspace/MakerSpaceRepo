
require 'rails_helper'

RSpec.describe ProjectKitsController, type: :controller do

  describe "GET #index" do

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

  describe "GET /new" do

    context "mark_delivered" do

      it 'should show the new page' do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to have_http_status(:success)
      end

      it 'should show redirect the user' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :new
        expect(response).to redirect_to root_path
        expect(flash[:alert]).to eq('You cannot access this area.')
      end

    end

  end

  describe "POST /create" do

    context "create" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        @pp = create(:proficient_project, :with_kit)
        @user = create(:user, :volunteer_with_dev_program)
      end

      it 'should create a kit' do
        expect{ post :create, params: {project_kit: {user_id: @user.id, proficient_project_id: @pp.id}} }.to change(ProjectKit, :count).by(1)
        expect(response).to redirect_to project_kits_path
      end

      it 'should fail to create a kit' do
        expect{ post :create, params: {project_kit: {user_id: "", proficient_project_id: @pp.id}} }.to change(ProjectKit, :count).by(0)
        expect(response).to redirect_to project_kits_path
      end

    end

  end

  describe "DELETE /destroy" do

    context "destroy" do

      before(:each) do
        admin = create(:user, :admin)
        session[:user_id] = admin.id
        session[:expires_at] = Time.zone.now + 10000
        @kit = create(:project_kit)
      end

      it 'should create a kit' do
        expect{ delete :destroy, params: {id: @kit.id}}.to change(ProjectKit, :count).by(-1)
        expect(response).to redirect_to project_kits_path
      end

      it 'should fail to create a kit' do
        expect{ delete :destroy, params: {id: ""}}.to change(ProjectKit, :count).by(0)
        expect(response).to redirect_to project_kits_path
      end

    end

  end

  describe "GET #populate_kit_users" do

    context "populate_kit_users" do

      it 'should get the users that has been searched' do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
        get :populate_kit_users, params: {search: user.name}
        expect(JSON.parse(response.body)['users'][0]['id']).to eq(user.id)
      end

    end

  end

  describe "GET #mark_delivered" do

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




