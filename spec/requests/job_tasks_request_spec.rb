# frozen_string_literal: true

require "rails_helper"

# Characterization spec for JobTasksController (chunk 6 "JobOrders").
#
# Pins the CURRENT observable behavior of the wizard/step machinery so a later
# refactor can prove no change. Notable current behaviors pinned here:
# * The controller has NO `signed_in` / `grant_access` gate at all — guests can
#   create AND destroy tasks on any order; `update` only checks that
#   `current_user` is the order owner or an admin.
# * `edit` renders any step for anyone (ownership is not checked).
# * The route is verb-bespoke: POST /job_orders/:job_order_id/task (create),
#   GET/PATCH/PUT/DELETE /job_orders/:job_order_id/task/:id.
# * Rails 8.1 test env maps app errors to a 500 (debug page) and
#   ActiveRecord::RecordNotFound to a 404 — both are pinned as-is.
RSpec.describe "JobTasks (HTTP contract)", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:other) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    seed_job_types!
  end

  def order_with_task!(status_key: :draft, owner_user: owner, title: "Task #1")
    make_job_order!(owner: owner_user, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  def wizard_path_for(order, task, step)
    edit_job_order_job_task_path(order, task, step: step)
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  # ------------------------------------------------------------- POST create

  describe "POST /job_orders/:job_order_id/task (create)" do
    it "appends the next numbered task for the signed-in owner and redirects to wizard step 1" do
      order = order_with_task!
      session_login!(owner)

      expect do
        post job_order_job_tasks_path(order)
      end.to change { order.reload.job_tasks.count }.by(1)

      task = order.job_tasks.last
      expect(task.title).to eq("Task #2")
      expect(task.job_type).to be_nil
      expect(response).to redirect_to(wizard_path_for(order, task, 1))
    end

    # WART-PIN: the numbering SQL uses the Postgres regexp "Task ([0-9]+)"
    # against titles that actually are "Task #N" — the "#" never matches, so
    # SUBSTRING returns NULL and the "highest existing number" is always 0.
    # Numbering is therefore purely count-based (max(count) + 1): with a gapped
    # "Task #1"/"Task #5" pair it happily produces "Task #3".
    it "numbers from the row count — the 'highest Task #N' SQL never matches the # marker (wart)" do
      order = order_with_task!
      order.job_tasks.create!(title: "Task #5")
      session_login!(owner)

      post job_order_job_tasks_path(order)
      expect(order.reload.job_tasks.last.title).to eq("Task #3")
    end

    it "starts at Task #1 on a taskless order" do
      order = make_job_order!(owner: owner)
      order.job_tasks.destroy_all
      session_login!(owner)

      post job_order_job_tasks_path(order)
      expect(order.reload.job_tasks.last.title).to eq("Task #1")
    end

    # WART: create has no signed-in gate — an anonymous request can append
    # tasks to any job order.
    it "lets a GUEST append a task to any order and still redirects to the wizard" do
      order = order_with_task!
      expect do
        post job_order_job_tasks_path(order)
      end.to change { order.reload.job_tasks.count }.by(1)

      expect(order.job_tasks.last.title).to eq("Task #2")
      expect(response).to redirect_to(wizard_path_for(order, order.job_tasks.last, 1))
    end

    it "500 (RecordNotFound → not found) for an unknown job order" do
      post "/job_orders/999_999_999/task"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- GET edit

  describe "GET /job_orders/:job_order_id/task/:id/edit" do
    it "renders wizard step 1 (order type) for the owner" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      get wizard_path_for(order, task, 1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 1/4)")
      expect(response.body).to include("Job Type (required)*")
      expect(response.body).to include("Next Step")
      expect(response.body).to include('name="job_task[job_type_id]"')
      # The Design Services type is excluded from the select…
      ds = JobType.find_by!(name: "Design Services")
      expect(response.body).not_to include("<option value=\"#{ds.id}\"")
      # …but its description card still renders.
      expect(response.body).to include("job_type_#{ds.id}_description")
    end

    it "renders the service step (2) with the task's job type" do
      order = order_with_task!
      task = order.job_tasks.first
      task.update!(job_type: JobType.find_by!(name: "3D Print"))
      session_login!(owner)

      get wizard_path_for(order, task, 2)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 2/4)")
      expect(response.body).to match(/<input[^>]*name="step"[^>]*value="3"/)
    end

    it "renders the options step (3) even with no seeded options" do
      order = order_with_task!
      task = order.job_tasks.first
      task.update!(job_type: JobType.find_by!(name: "3D Print"))
      session_login!(owner)

      get wizard_path_for(order, task, 3)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 3/4)")
    end

    it "renders the submission step (4)" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      get wizard_path_for(order, task, 4)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 4/4)")
      expect(response.body).to match(/<input[^>]*name="step"[^>]*value="5"/)
      expect(response.body).to include("Add Another Task")
    end

    it "redirects unknown step numbers to the order page" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      get wizard_path_for(order, task, 99)
      expect(response).to redirect_to(job_order_path(order))
    end

    it "500 (JobType find on nil → not found) for step 2 on a task without a job type" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      get wizard_path_for(order, task, 2)
      expect(response).to have_http_status(:not_found)
    end

    # WART: no ownership/permission gate — any signed-in user (and even guests)
    # can open the wizard steps of someone else's order.
    it "renders the wizard for a non-owner regular user (no gate — wart)" do
      order = order_with_task!
      session_login!(other)
      get wizard_path_for(order, order.job_tasks.first, 1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 1/4)")
    end

    it "renders the wizard for a GUEST (no gate — wart)" do
      order = order_with_task!
      get wizard_path_for(order, order.job_tasks.first, 1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Job Task (Step 1/4)")
    end

    it "renders the Design Services specialization from the template (step ignored)" do
      order = order_with_task!
      task = order.job_tasks.first
      task.update!(job_type: JobType.find_by!(name: "Design Services"))
      session_login!(owner)

      get wizard_path_for(order, task, 1)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Job Order")
      expect(response.body).to include('name="comments"')
      expect(response.body).to match(/<input[^>]*name="step"[^>]*value="5"/)
    end

    it "404s when the task belongs to a different order (RecordNotFound)" do
      order = order_with_task!
      foreign_task = order_with_task!(
        owner_user: owner, title: "Task #1"
      ).job_tasks.first

      session_login!(owner)
      get wizard_path_for(order, foreign_task, 1)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for an unknown job order" do
      order = order_with_task!
      session_login!(owner)
      get "/job_orders/999_999_999/task/#{order.job_tasks.first.id}/edit"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- PATCH update

  describe "PATCH /job_orders/:job_order_id/task/:id (update)" do
    # The owner gate is the FIRST thing in the action: only the order owner or
    # an admin may update; everyone else is told the order "hasn't been found"
    # and redirected to the client index.
    it "bounces non-owners (signed users) with the not-found redirect and changes nothing" do
      order = order_with_task!
      task = order.job_tasks.first

      session_login!(other)
      patch job_order_job_task_path(order, task),
            params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "3D Print").id } }

      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert])
        .to eq(I18n.t("job_orders.alerts.job_order_not_found"))
      expect(task.reload.job_type).to be_nil
    end

    it "bounces guests the same way (Unauthorized => User.new is neither owner nor admin)" do
      order = order_with_task!
      task = order.job_tasks.first
      patch job_order_job_task_path(order, task),
            params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "3D Print").id } }
      expect(response).to redirect_to(job_orders_path)
      expect(task.reload.job_type).to be_nil
    end

    context "as the owner" do
      before { session_login!(owner) }

      it "advances to the next wizard step after setting the job type" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task),
              params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "3D Print").id } }

        expect(response)
          .to redirect_to(wizard_path_for(order, task, 2))
        expect(task.reload.job_type.name).to eq("3D Print")
      end

      it "records a chat message from #comments (sender = the owner)" do
        order = order_with_task!
        task = order.job_tasks.first

        expect do
          patch job_order_job_task_path(order, task),
                params: { step: "1", comments: "Please use the resin printer" }
        end.to change { order.reload.chat_messages.count }.by(1)

        message = order.chat_messages.last
        expect(message.message).to eq("Please use the resin printer")
        expect(message.sender).to eq(owner)
      end

      it "forwards to step 3 from step 2" do
        order = order_with_task!
        task = order.job_tasks.first
        task.update!(job_type: JobType.find_by!(name: "3D Print"))

        patch job_order_job_task_path(order, task), params: { step: "2" }
        expect(response).to redirect_to(wizard_path_for(order, task, 3))
      end

      it "saves the submitted task in a draft state and back to the order page" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task), params: { step: "2", save_draft: "true" }
        expect(response).to redirect_to(job_order_path(order))
        expect(status_names(order)).to eq(["Draft"])
      end

      it "spawns 'Task #N+1' when the form asks for another task" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task),
              params: { step: "4", add_another: "true" }
        expect(response).to have_http_status(:redirect)
        new_task = order.reload.job_tasks.last
        expect(new_task.title).to eq("Task #2")
        expect(response).to redirect_to(wizard_path_for(order, new_task, 1))
      end

      context "step 3 task options" do
        def usable_option!
          option = JobOption.create!(name: "Expedited Processing", fee: 7.5)
          option.job_types << JobType.find_by!(name: "3D Print")
          option
        end

        it "persists selected options (array form, like the checkbox form post)" do
          order = order_with_task!
          task = order.job_tasks.first
          task.update!(job_type: JobType.find_by!(name: "3D Print"))
          option = usable_option!

          patch job_order_job_task_path(order, task), params: {
            step: "3",
            job_task: { job_task_options_attributes: [{ job_option_id: option.id }] }
          }

          expect(response).to redirect_to(wizard_path_for(order, task, 4))
          expect(task.reload.job_options).to contain_exactly(option)
        end

        it "replaces deselected options (and their quote options) when re-submitting step 3" do
          option = JobOption.create!(name: "Expedited Processing", fee: 7.5)
          option.job_types << JobType.find_by!(name: "3D Print")
          later_option = JobOption.create!(name: "Polish", fee: 9.0)
          later_option.job_types << JobType.find_by!(name: "3D Print")

          order = order_with_task!
          task = order.job_tasks.first
          task.update!(job_type: JobType.find_by!(name: "3D Print"))
          task.job_task_options.create!(job_option: option)
          task.build_job_task_quote(price: 5).save!
          task.job_task_quote.job_task_quote_options.create!(job_option: option, price: 1)

          patch job_order_job_task_path(order, task), params: {
            step: "3",
            job_task: { job_task_options_attributes: [{ job_option_id: later_option.id }] }
          }

          expect(task.reload.job_options).to contain_exactly(later_option)
          # The deselected option's quote line was removed along with it.
          expect(task.job_task_quote.job_task_quote_options).to be_empty
        end

        it "keeps unsubmitted options at other steps (destroy guard is step-3 only)" do
          option = JobOption.create!(name: "Expedited Processing", fee: 7.5)
          option.job_types << JobType.find_by!(name: "3D Print")

          order = order_with_task!
          task = order.job_tasks.first
          task.update!(job_type: JobType.find_by!(name: "3D Print"))
          task.job_task_options.create!(job_option: option)

          patch job_order_job_task_path(order, task), params: { step: "4" }
          expect(task.reload.job_options).to contain_exactly(option)
        end
      end

      it "attaches an allowed user file (STL) and jumps to step 3" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task),
              params: { step: "2", job_task: { user_files: [FilesTestHelper.stl] } }

        expect(response).to redirect_to(wizard_path_for(order, task, 3))
        expect(task.reload.user_files).to be_present
      end

      it "bounces a disallowed file (MP4) back to the step with the validation copy" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task),
              params: { step: "2", job_task: { user_files: [FilesTestHelper.mp4] } }

        expect(response)
          .to redirect_to(wizard_path_for(order, task, 2))
        expect(task.reload.user_files).to be_empty
        expect(flash[:alert]).to include("User files file should be one of")
      end

      it "submits for approval on the final step (STAFF_APPROVAL + mail + notice)" do
        order = order_with_task!
        task = order.job_tasks.first
        task.update!(job_type: JobType.find_by!(name: "3D Print"))

        expect do
          patch job_order_job_task_path(order, task),
                params: { step: "4", comments: "done" }
        end.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(response).to redirect_to(job_order_path(order))
        expect(flash[:notice])
          .to eq(I18n.t("job_orders.alerts.job_order_submitted_for_approval"))
        expect(status_names(order)).to eq(["Draft", "Waiting for Staff Approval"])
        expect(order.job_order_statuses.last.user).to eq(owner)
        expect(ActionMailer::Base.deliveries.last.subject)
          .to eq("A new Job Order has been submitted")
        expect(ActionMailer::Base.deliveries.last.to).to eq(["makerspace@uottawa.ca"])
      end

      # N+1 pinned: see defects.md D-PERF04
      it "stays a Draft when ANOTHER task is still incomplete (submit silently skipped)", skip_bullet: true do
        order = order_with_task!
        order.job_tasks.create!(title: "Task #2")
        task = order.job_tasks.find_by(title: "Task #1")
        task.update!(job_type: JobType.find_by!(name: "3D Print"))

        expect do
          patch job_order_job_task_path(order, task), params: { step: "4" }
        end.not_to(change { ActionMailer::Base.deliveries.size })

        expect(response).to redirect_to(job_order_path(order))
        expect(flash[:notice]).to be_nil
        expect(status_names(order)).to eq(["Draft"])
      end

      it "does not re-submit when the order already left Draft (status guard)" do
        order = order_with_task!(status_key: :staff_approval)
        task = order.job_tasks.first
        task.update!(job_type: JobType.find_by!(name: "3D Print"))

        patch job_order_job_task_path(order, task), params: { step: "4" }
        expect(status_names(order)).to eq(["Waiting for Staff Approval"])
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "treats a Design Services task type as a submission too (any step)" do
        order = order_with_task!
        task = order.job_tasks.first

        expect do
          patch job_order_job_task_path(order, task),
                params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "Design Services").id } }
        end.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(response).to redirect_to(job_order_path(order))
        expect(status_names(order)).to eq(["Draft", "Waiting for Staff Approval"])
      end
    end

    context "as an admin (may update other users' orders)" do
      before { session_login!(admin) }

      it "updates someone else's task" do
        order = order_with_task!
        task = order.job_tasks.first

        patch job_order_job_task_path(order, task),
              params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "Laser Cut").id } }
        expect(response).to redirect_to(wizard_path_for(order, task, 2))
        expect(task.reload.job_type.name).to eq("Laser Cut")
      end
    end

    it "404s (RecordNotFound) when the task id is unknown" do
      order = order_with_task!
      session_login!(owner)
      patch job_order_job_task_path(order, id: "987_654_321"), params: { step: "1" }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- DELETE destroy

  # WART: destroy has no permission check of any kind.
  describe "DELETE /job_orders/:job_order_id/task/:id (destroy)" do
    it "lets the owner delete and redirects back to the order page with the flash" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      expect do
        delete job_order_job_task_path(order, task)
      end.to change(JobTask, :count).by(-1)

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:notice]).to eq("Task was successfully deleted.")
      task.destroyed?
      expect(JobTask.exists?(task.id)).to be(false)
    end

    it "lets a stranger delete someone else's task (wart)" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(other)

      expect do
        delete job_order_job_task_path(order, task)
      end.to change(JobTask, :count).by(-1)
      expect(response).to redirect_to(job_order_path(order))
    end

    it "even lets a GUEST delete a task (wart)" do
      order = order_with_task!
      task = order.job_tasks.first

      expect do
        delete job_order_job_task_path(order, task)
      end.to change(JobTask, :count).by(-1)
      expect(response).to redirect_to(job_order_path(order))
    end

    it "answers 204 for the JSON API shape" do
      order = order_with_task!
      task = order.job_tasks.first
      session_login!(owner)

      delete job_order_job_task_path(order, task), as: :json
      expect(response).to have_http_status(:no_content)
      expect(JobTask.exists?(task.id)).to be(false)
    end

    it "404s (RecordNotFound) for a task in a DIFFERENT order" do
      order = order_with_task!
      foreign_task = order_with_task!(owner_user: owner).job_tasks.first
      session_login!(owner)

      delete job_order_job_task_path(order, foreign_task)
      expect(response).to have_http_status(:not_found)
      expect(JobTask.exists?(foreign_task.id)).to be(true)
    end
  end
end
