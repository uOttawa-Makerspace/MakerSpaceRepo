require "rails_helper"

RSpec.describe Admin::JobOptionsController, type: :controller do
  let(:admin) { create(:user, :admin) }
  let!(:job_option) { create(:job_option) }

  before do
    session[:user_id] = admin.id
  end

  describe "GET #new" do
    it "returns a successful response" do
      get :new
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new JobOption and redirects" do
        expect do
          post :create, params: { job_option: attributes_for(:job_option) }
        end.to change(JobOption, :count).by(1)

        expect(response).to redirect_to(settings_job_orders_path)
        expect(flash[:notice]).to eq("The option has been created!")
      end
    end

    context "with invalid params" do
      it "does not create and shows alert" do
        expect do
          post :create, params: { job_option: { name: "" } }
        end.not_to change(JobOption, :count)

        expect(response).to redirect_to(settings_job_orders_path)
        expect(flash[:alert]).to eq("There was an error while creating the option.")
      end
    end
  end

  describe "GET #edit" do
    it "returns a successful response" do
      get :edit, params: { id: job_option.id }
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH #update" do
    it "creates a copy with updated attributes" do
      expect do
        patch :update, params: { id: job_option.id, job_option: { name: "Updated Name" } }
      end.to change(JobOption, :count).by(1)

      expect(JobOption.last.name).to include("Updated Name")
    end
  end

  describe "DELETE #destroy" do
    it "soft deletes the option" do
      delete :destroy, params: { id: job_option.id }
      expect(job_option.reload.is_deleted).to be_truthy
    end

    it "shows alert if destroy fails" do
      allow_any_instance_of(JobOption).to receive(:destroy).and_return(false)

      delete :destroy, params: { id: job_option.id }

      expect(response).to redirect_to(settings_job_orders_path)
      expect(flash[:alert]).to eq("An error occurred while deleting the option.")
    end
  end
end
