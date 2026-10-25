# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for JobTasksController: the custom-service branch of
# update, nested option destruction, step-3 corners, role columns (staff,
# admin) and the numbering/soft-delete quirks.

RSpec.describe "JobTasks gaps", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:print_type) { JobType.find_by!(name: "3D Print") }

  before do
    seed_job_statuses!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def order_with_task!(status_key: :draft, title: "Task #1")
    make_job_order!(owner: owner, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def wizard(order, task, step)
    edit_job_order_job_task_path(order, task, step: step)
  end

  # ------------------------------------------------------------- custom service

  describe "update with a custom service (job_service_id = 'custom')" do
    let(:order) { order_with_task! }
    let(:task) { order.job_tasks.first }
    let(:group) { create(:job_service_group, job_type: print_type, name: "Material") }

    before do
      task.update!(job_type: print_type)
      session_login!(owner)
    end

    def patch_custom(target_task, name, group_id = group.id)
      patch job_order_job_task_path(order, target_task),
            params: { step: "2", "job_service_name_#{group_id}" => name,
                      job_task: { job_service_id: "custom" } }
    end

    it "creates a user_created service for the order and group, attaches it to the task and moves to step 3" do
      expect { patch_custom(task, "Exotic filament") }.to change(JobService, :count).by(1)

      service = JobService.order(:id).last
      expect(service.name).to eq("Exotic filament")
      expect(service.user_created).to be(true)
      expect(service.job_service_group_id).to eq(group.id)
      # the HABTM join row to the order is NEVER written (only the service is saved)
      expect(order.job_services).to be_empty
      expect(task.reload.job_service).to eq(service)
      expect(response).to redirect_to(wizard(order, task, 3))
    end

    # WART(D-J41): the review (and the code's find_or_initialize_by) suggest ONE
    # custom service per (order, group) shared and renamed across tasks. In fact
    # the HABTM join is never persisted, so the lookup never finds the earlier
    # service: every submit creates a NEW user_created service, tasks keep their
    # own, and repeated submits orphan the previous ones.
    it "creates a separate custom service per submit instead of reusing one per order and group" do
      second = order.job_tasks.create!(title: "Task #2", job_type: print_type)
      patch_custom(task, "First name")
      patch_custom(second, "Second name")
      patch_custom(second, "Second name again")

      expect(JobService.where(user_created: true).pluck(:name))
        .to match_array(["First name", "Second name", "Second name again"])
      expect(task.reload.job_service.name).to eq("First name")
      expect(second.reload.job_service.name).to eq("Second name again")
    end

    # WART(D-J41): without a name the literal "custom" reaches the FK column
    it "500s (InvalidForeignKey) when 'custom' is posted without any name (the marker is cast to service id 0)" do
      expect { patch_custom(task, "") }.not_to change(JobService, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("ActiveRecord::InvalidForeignKey")
      expect(task.reload.job_service_id).to be_nil
    end
  end

  # ------------------------------------------------------------- options

  describe "update with job task options" do
    let(:order) { order_with_task! }
    let(:task) { order.job_tasks.first }
    let(:option) { JobOption.create!(name: "Polish", fee: 2).tap { |o| o.job_types << print_type } }
    let(:other_option) { JobOption.create!(name: "Paint", fee: 4).tap { |o| o.job_types << print_type } }

    before do
      task.update!(job_type: print_type)
      session_login!(owner)
    end

    it "skips options flagged _destroy=1 on the submitted list" do
      patch job_order_job_task_path(order, task), params: {
        step: "3",
        job_task: { job_task_options_attributes: [
          { job_option_id: option.id }, { job_option_id: other_option.id, _destroy: "1" }
        ] }
      }
      expect(task.reload.job_options).to contain_exactly(option)
    end

    it "removes every option when step 3 is submitted with none selected" do
      task.job_task_options.create!(job_option: option)
      patch job_order_job_task_path(order, task), params: { step: "3" }
      expect(task.reload.job_options).to be_empty
      expect(response).to redirect_to(wizard(order, task, 4))
    end

    it "attaches an option file to the selected option" do
      patch job_order_job_task_path(order, task), params: {
        step: "3",
        job_task: { job_task_options_attributes: [{ job_option_id: option.id, option_file: FilesTestHelper.stl }] }
      }
      expect(task.reload.job_task_options.first.option_file).to be_attached
    end

    it "shows a deleted option on step 3 only while it is still selected by the task" do
      option.update!(is_deleted: true)
      other_option # stays selectable
      get wizard(order, task, 3)
      expect(response.body).not_to include("Polish")

      task.job_task_options.create!(job_option: option)
      get wizard(order, task, 3)
      expect(response.body).to include("Polish", "Paint")
    end
  end

  # ------------------------------------------------------------- update corners

  describe "update corners" do
    let(:order) { order_with_task! }
    let(:task) { order.job_tasks.first }

    it "redirects an update without a job_task key to the next wizard step (nothing to update)" do
      session_login!(owner)
      patch job_order_job_task_path(order, task), params: { step: "1" }
      expect(response).to redirect_to(wizard(order, task, 2))
    end

    it "treats a missing step as 0 and goes to step 1" do
      session_login!(owner)
      patch job_order_job_task_path(order, task), params: { job_task: { job_type_id: print_type.id } }
      expect(response).to redirect_to(wizard(order, task, 1))
      expect(task.reload.job_type).to eq(print_type)
    end

    it "bounces a staff member who is neither owner nor admin" do
      session_login!(staff)
      patch job_order_job_task_path(order, task), params: { step: "1", job_task: { job_type_id: print_type.id } }
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.job_order_not_found"))
      expect(task.reload.job_type).to be_nil
    end

    it "records the admin as the status user when the admin submits someone else's order" do
      task.update!(job_type: print_type)
      session_login!(admin)
      patch job_order_job_task_path(order, task), params: { step: "4" }
      expect(status_names(order)).to eq(["Draft", "Waiting for Staff Approval"])
      expect(order.job_order_statuses.last.user).to eq(admin)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["makerspace@uottawa.ca"])
    end

    it "flashes the validation error and redirects back to the step when a disallowed file is posted (with a referer)" do
      session_login!(owner)
      patch job_order_job_task_path(order, task),
            params: { step: "2", job_task: { user_files: [FilesTestHelper.mp4] } },
            headers: { "HTTP_REFERER" => wizard(order, task, 2) }
      expect(response).to redirect_to(wizard(order, task, 2))
      expect(flash[:alert]).to include("User files file should be one of")
    end

    it "ignores blank comments (no chat message)" do
      session_login!(owner)
      expect do
        patch job_order_job_task_path(order, task), params: { step: "1", comments: "" }
      end.not_to change(ChatMessage, :count)
    end

    it "accepts a job_service_id that belongs to another order's group (no ownership check)" do
      foreign_group = create(:job_service_group, job_type: JobType.find_by!(name: "Laser Cut"))
      foreign_service = create(:job_service, job_service_group: foreign_group)
      task.update!(job_type: print_type)
      session_login!(owner)
      patch job_order_job_task_path(order, task),
            params: { step: "2", job_task: { job_service_id: foreign_service.id } }
      expect(task.reload.job_service).to eq(foreign_service)
    end

    it "does not stop the owner from changing the task once the order left Draft (see job_orders_security_request_spec D-J35)" do
      sent = order_with_task!(status_key: :staff_approval)
      session_login!(owner)
      patch job_order_job_task_path(sent, sent.job_tasks.first),
            params: { step: "1", job_task: { job_type_id: print_type.id } }
      expect(sent.job_tasks.first.reload.job_type).to eq(print_type)
    end
  end

  # ------------------------------------------------------------- create / destroy corners

  describe "create and destroy corners" do
    it "lets staff and admin create tasks on someone else's order" do
      order = order_with_task!
      [staff, admin].each do |user|
        session_login!(user)
        expect { post job_order_job_tasks_path(order) }.to change { order.job_tasks.count }.by(1)
        expect(response).to have_http_status(:redirect)
      end
    end

    # WART(D-J18): numbering falls back to the row count, so deleting an early
    # task makes the next one reuse an existing title.
    it "produces a duplicate 'Task #2' title after deleting Task #1 from [#1, #2]" do
      order = order_with_task!
      order.job_tasks.create!(title: "Task #2")
      session_login!(owner)
      delete job_order_job_task_path(order, order.job_tasks.find_by!(title: "Task #1"))

      post job_order_job_tasks_path(order)
      expect(order.reload.job_tasks.order(:id).pluck(:title)).to eq(["Task #2", "Task #2"])
    end

    it "lets staff delete a task" do
      order = order_with_task!
      session_login!(staff)
      expect { delete job_order_job_task_path(order, order.job_tasks.first) }.to change(JobTask, :count).by(-1)
    end

    # WART(D-J48): task routes use a plain JobOrder.find, so soft-deleted orders stay addressable
    it "still creates and edits tasks on a soft-deleted order" do
      order = order_with_task!
      order.update!(is_deleted: true)
      session_login!(owner)
      expect { post job_order_job_tasks_path(order) }.to change { order.job_tasks.count }.by(1)
      get wizard(order, order.job_tasks.first, 1)
      expect(response).to have_http_status(:ok)
    end

    it "redirects a missing step on edit to the order page" do
      order = order_with_task!
      session_login!(owner)
      get edit_job_order_job_task_path(order, order.job_tasks.first)
      expect(response).to redirect_to(job_order_path(order))
    end
  end
end
