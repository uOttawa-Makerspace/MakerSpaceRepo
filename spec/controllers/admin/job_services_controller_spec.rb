require "rails_helper"

RSpec.describe Admin::JobServicesController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @job_service = create(:job_service)
  end

  describe "GET /new" do
    context "logged as admin" do
      it "should return a 200" do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /create" do
    context "logged as admin" do
      it "should create an job service and redirect" do
        params =
          FactoryBot.attributes_for(:job_service_group).merge(
            job_service_group_id: create(:job_service_group).id
          )
        expect { post :create, params: { job_service: params } }.to change(
          JobService,
          :count
        ).by(1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        get :edit, params: { id: @job_service.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "should update the job service" do
        patch :update,
              params: {
                id: @job_service.id,
                job_service: {
                  name: "abc123"
                }
              }
        expect(response).to redirect_to settings_job_orders_path
        expect(JobService.find(@job_service.id).name).to eq("abc123")
      end
    end
  end

  describe "DELETE /destroy" do
    context "logged as admin" do
      it "should destroy the job service group" do
        expect { delete :destroy, params: { id: @job_service.id } }.to change(
          JobService,
          :count
        ).by(-1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  after(:all) { JobService.destroy_all }
end
