require 'rails_helper'
include FilesTestHelper

RSpec.describe ProjectRequirementsController, type: :controller do
  before(:all) do
    @admin = create(:user, :admin)
  end

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe 'POST /create' do
    context 'logged as regular user' do
      it 'should go to root page' do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        pp = create(:proficient_project)
        required_pp = create(:proficient_project)
        expect{ post :create, params: {id: pp, required_project_id: required_pp} }.to change(ProjectRequirement, :count).by(0)
        expect(response).to redirect_to root_path
      end
    end

    context 'logged as admin' do
      it 'should create a requirement' do
        pp = create(:proficient_project)
        required_pp = create(:proficient_project)
        expect{ post :create, params: {id: pp, required_project_id: required_pp.id} }.to change(ProjectRequirement, :count).by(1)
        expect(response).to redirect_to proficient_project_path(pp.id)
        expect(flash[:notice]).to eq('Required project added.')
      end

      it 'should fail to create a requirement' do
        pp = create(:proficient_project)
        required_pp = create(:proficient_project)
        expect{ post :create, params: {id: pp.id, required_project_id: required_pp} }.to change(ProjectRequirement, :count).by(1)
        expect{ post :create, params: {id: pp.id, required_project_id: required_pp} }.to change(ProjectRequirement, :count).by(0)
        expect(response).to redirect_to proficient_project_path(pp.id)
        expect(flash[:alert]).to eq('Something went wrong. Try again.')
      end
    end
  end

  describe 'DELETE /destroy' do
    context 'destroy requirement' do
      it 'should delete the requirement' do
        pp = create(:proficient_project)
        required_pp = create(:proficient_project)
        ProjectRequirement.create(proficient_project_id: pp.id, required_project_id: required_pp.id)
        expect { delete :destroy, params: {id: ProjectRequirement.last.id} }.to change(ProjectRequirement, :count).by(-1)
        expect(response).to redirect_to proficient_project_path(pp.id)
      end
    end
  end

end

