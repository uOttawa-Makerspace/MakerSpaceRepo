require "rails_helper"

RSpec.describe JobTasksController, type: :controller do
  let(:user) { create(:user) }
  let(:job_order) { create(:job_order, user: user) }
  let(:job_type) { create(:job_type) }
  let(:job_service) { create(:job_service) }
  let!(:job_task) { create(:job_task, job_order: job_order, job_type: job_type, job_service: job_service) }

  before do
    session[:user_id] = user.id
  end

  describe "POST #create" do
    it "creates a job task and redirects to step 1" do
      expect do
        post :create, params: { job_order_id: job_order.id }
      end.to change(JobTask, :count).by(1)

      task = JobTask.last
      expect(response).to redirect_to(edit_job_order_job_task_path(job_order, task, step: 1))
    end
  end

  describe "DELETE #destroy" do
    it "deletes the job task and redirects" do
      expect do
        delete :destroy, params: { job_order_id: job_order.id, id: job_task.id }
      end.to change(JobTask, :count).by(-1)

      expect(response).to redirect_to(job_order_path(job_order))
    end
  end

  describe "GET #edit" do
    it "renders step 1 (order_type) template" do
      get :edit, params: { job_order_id: job_order.id, id: job_task.id, step: 1 }
      expect(response).to render_template("job_orders/wizard/order_type")
    end
  end

  describe "PATCH #update" do
    it "updates job_task and redirects to next step" do
      patch :update, params: {
        job_order_id: job_order.id,
        id: job_task.id,
        step: 1,
        job_task: {
          job_service_id: job_service.id
        }
      }

      expect(response).to redirect_to(edit_job_order_job_task_path(job_order, job_task, step: 2))
    end
  end
end