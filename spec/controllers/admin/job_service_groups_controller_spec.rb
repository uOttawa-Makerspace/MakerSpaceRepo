require "rails_helper"

RSpec.describe Admin::JobServiceGroupsController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @job_service_group = create(:job_service_group)
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
      it "should create an job service group and redirect" do
        params =
          FactoryBot.attributes_for(:job_service_group).merge(
            job_type_id: create(:job_type).id
          )
        expect do
          post :create, params: { job_service_group: params }
        end.to change(JobServiceGroup, :count).by(1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        get :edit, params: { id: @job_service_group.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "soft updates the job service group by duplicating it with new attributes" do
        original_id = @job_service_group.id

        expect do
          patch :update,
                params: {
                  id: original_id,
                  job_service_group: {
                    name: "abc123"
                  }
                }
        end.to change(JobServiceGroup, :count).by(1)

        expect(response).to redirect_to(settings_job_orders_path)

        expect(JobServiceGroup.find(original_id).is_deleted).to be true

        new_record = JobServiceGroup.order(:created_at).last
        expect(new_record.name).to eq("abc123")
        expect(new_record.is_deleted).to be false
      end
    end
  end

  after(:all) { JobServiceGroup.destroy_all }
end
