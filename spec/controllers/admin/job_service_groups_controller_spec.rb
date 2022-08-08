require 'rails_helper'

RSpec.describe Admin::JobServiceGroupsController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @job_service_group = create(:job_service_group)
  end

  describe 'GET /new' do
    context 'logged as admin' do
      it 'should return a 200' do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /create' do
    context 'logged as admin' do
      it 'should create an job service group and redirect' do
        params =  FactoryBot.attributes_for(:job_service_group).merge(job_type_id: create(:job_type).id)
        expect { post :create, params: {job_service_group: params} }.to change(JobServiceGroup, :count).by(1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  describe "GET /edit" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :edit, params: {id: @job_service_group.id}
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /update' do
    context 'logged as admin' do
      it 'should update the job service group' do
        patch :update, params: {id: @job_service_group.id, job_service_group: {name: "abc123"} }
        expect(response).to redirect_to settings_job_orders_path
        expect(JobServiceGroup.find(@job_service_group.id).name).to eq("abc123")
      end
    end
  end

  describe "DELETE /destroy" do
    context 'logged as admin' do
      it 'should destroy the job service group' do
        expect { delete :destroy, params: {id: @job_service_group.id} }.to change(JobServiceGroup, :count).by(-1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  after(:all) do
    JobServiceGroup.destroy_all
  end
end




