require "rails_helper"

RSpec.describe Admin::JobOptionsController, type: :controller do
  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    @option = create(:job_option)
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
      it "should create an option and redirect" do
        params = FactoryBot.attributes_for(:job_option)
        expect { post :create, params: { job_option: params } }.to change(
          JobOption,
          :count
        ).by(1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  describe "GET /edit" do
    context "logged as admin" do
      it "should return 200 response" do
        get :edit, params: { id: @option.id }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PATCH /update" do
    context "logged as admin" do
      it "should update the option" do
        patch :update,
              params: {
                id: @option.id,
                job_option: {
                  name: "abc123"
                }
              }
        expect(response).to redirect_to settings_job_orders_path
        expect(JobOption.find(@option.id).name).to eq("abc123")
      end
    end
  end

  describe "DELETE /destroy" do
    context "logged as admin" do
      it "should destroy the option" do
        expect { delete :destroy, params: { id: @option.id } }.to change(
          JobOption,
          :count
        ).by(-1)
        expect(response).to redirect_to settings_job_orders_path
      end
    end
  end

  after(:all) { JobOption.destroy_all }
end
