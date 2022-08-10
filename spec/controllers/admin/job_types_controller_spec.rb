require "rails_helper"

RSpec.describe Admin::JobTypesController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @job_type = create(:job_type)
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
      it "should create an job type and redirect" do
        params = FactoryBot.attributes_for(:job_type)
        expect { post :create, params: { job_type: params } }.to change(
          JobType,
          :count
        ).by(1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        get :edit, params: { id: @job_type.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "should update the job type" do
        patch :update,
              params: {
                id: @job_type.id,
                job_type: {
                  name: "abc123"
                }
              }
        expect(response).to redirect_to settings_job_orders_path
        expect(JobType.find(@job_type.id).name).to eq("abc123")
      end
    end
  end

  after(:all) { JobType.destroy_all }
end
