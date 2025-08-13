require "rails_helper"

RSpec.describe Admin::JobServicesController, type: :controller do
  let(:admin) { create(:user, :admin) }
  let!(:job_service) { create(:job_service) }

  before do
    session[:user_id] = admin.id
  end

  describe "GET #new" do
    it "returns 200" do
      get :new
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST #create" do
    it "creates a job service and redirects" do
      params = attributes_for(:job_service).merge(
        job_service_group_id: create(:job_service_group).id
      )

      expect do
        post :create, params: { job_service: params }
      end.to change(JobService, :count).by(1)

      expect(response).to redirect_to(settings_job_orders_path)
      expect(flash[:notice]).to eq("The Service has been created!")
    end
  end

  describe "GET #edit" do
    it "returns 200" do
      get :edit, params: { id: job_service.id }
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH #update" do
    it "creates a copy with updated name instead of updating original" do
      expect do
        patch :update,
              params: { id: job_service.id, job_service: { name: "Updated Name" } }
      end.to change(JobService, :count).by(1)

      new_record = JobService.order(created_at: :desc).first
      expect(new_record.name).to include("Updated Name")
      expect(response).to redirect_to(settings_job_orders_path)
      expect(flash[:notice]).to eq("The Service has been updated")
    end
  end

  describe "DELETE #destroy" do
    it "soft deletes the job service and redirects" do
      delete :destroy, params: { id: job_service.id }
      
      expect(response).to redirect_to(settings_job_orders_path)
      expect(flash[:notice]).to eq("The Service has been deleted successfully")

      expect(job_service.reload.is_deleted).to be_truthy
    end
  end

  after(:all) do
    JobService.destroy_all
  end
end
