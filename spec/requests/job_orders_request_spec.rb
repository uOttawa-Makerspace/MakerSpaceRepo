# frozen_string_literal: true

require "rails_helper"

# Characterization spec for JobOrdersController (chunk 6 "JobOrders").
#
# Pins the CURRENT observable behavior of the 587-line god controller so a
# later refactor can prove no change. Everything below reflects the app as it
# runs today (Rails 8.1, devcontainer); warts are pinned, not fixed.
#
# Notes on the environment:
# * The test database has no reference data, while JobStatus resolves its
#   constants ONCE at boot (JobStatus.rb does find_by at class-body time).
#   Each example that exercises the status machine seeds the migration-shipped
#   reference rows and repoints the boot-time constants at them
#   (spec/support/job_orders_spec_helpers.rb) — mirroring how any deployed
#   environment looks (the rows exist there).
# * Authentication is a custom session; request specs use the real login POST
#   (the shipped sign_in_via_session shim infinite-loops in type: :request —
#   see spec/support/auth_helpers.rb; precedent sub_space_booking_request_spec).
# * Rails 8.1 maps `config.action_dispatch.show_exceptions = false` to
#   "resilient": raised app errors are reported and turned into a 500 (with a
#   debug page body, which we pin) instead of re-raising in the test.
# * `pay` renders a link from
#   JobOrder#checkout_link (a Shopify draft-order invoice URL); the examples
#   stub the Shopify GraphQL client boundary (`stub_shopify_admin!`, see
#   spec/support/shop_spec_helpers.rb), never the model.
# * Mail is pinned by DELIVERED outcome (`perform_enqueued_jobs` +
#   `ActionMailer::Base.deliveries`: recipient + subject), never by enqueue
#   mechanism.
RSpec.describe "JobOrders (HTTP contract)", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:other) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    ActionMailer::Base.deliveries.clear
  end

  # ------------------------------------------------------------- helpers

  def order_with_task!(owner:, status_key: :draft, title: "Task #1")
    make_job_order!(owner: owner, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  def advance_to!(order, status_key)
    row = JobStatus.find_by!(name: JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(status_key))
    order.job_order_statuses.create!(job_status: row, user: owner)
    order
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def http_login!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  # ------------------------------------------------------- auth gates

  # The guest gate (`ApplicationController#signed_in`) always redirects to
  # /login?back_to=<fullpath> WITHOUT any flash message (no alert is set).
  describe "auth gates" do
    it "redirects guests on index to the login page with a back_to target (no flash)" do
      get job_orders_path
      expect(response).to redirect_to(login_path(back_to: "/job_orders"))
      expect(flash[:alert]).to be_nil
    end

    it "redirects guests on show" do
      order = order_with_task!(owner: owner)
      get job_order_path(order)
      expect(response)
        .to redirect_to(login_path(back_to: "/job_orders/#{order.id}"))
    end

    it "redirects guests on new" do
      get new_job_orders_path
      expect(response).to redirect_to(login_path(back_to: "/job_orders/new"))
    end

    it "redirects guests on admin and settings" do
      get admin_job_orders_path
      expect(response).to redirect_to(login_path(back_to: "/job_orders/admin"))
      get settings_job_orders_path
      expect(response).to redirect_to(login_path(back_to: "/job_orders/settings"))
    end

    it "redirects guests on the staff-only status transitions" do
      order = order_with_task!(owner: owner)
      patch job_order_start_processing_path(order), params: { start_processing: "true" }
      expect(response)
        .to redirect_to(login_path)
    end
  end

  # ------------------------------------------------------- GET index

  describe "GET /job_orders (index)" do
    it "renders My Job Orders and, for a regular user, no admin link" do
      http_login!(owner)
      get job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("job_orders.public_page.my_job_orders"))
      expect(response.body).to include(I18n.t("job_orders.public_page.create_a_new_job_order"))
      expect(response.body).not_to include(I18n.t("job_orders.public_page.admin_page"))
    end

    # N+1 pinned: see defects.md D-PERF01
    it "splits draft orders (partly created) from submitted ones", skip_bullet: true do
      draft = order_with_task!(owner: owner, status_key: :draft)
      empty_draft = make_job_order!(owner: owner, status_key: :draft)
      submitted = order_with_task!(owner: owner, status_key: :staff_approval)

      http_login!(owner)
      get job_orders_path
      expect(response).to have_http_status(:ok)
      # The i18n copy contains an apostrophe which ERB HTML-escapes, so
      # pinning the raw translation string would never match the body.
      expect(response.body).to include("have been partly created")
      # A draft with tasks renders an "Order #N" continuation link...
      expect(response.body).to include("Order ##{draft.id}")
      # ...a draft without tasks gets NO link (its id appears nowhere)...
      expect(response.body).not_to include("Order ##{empty_draft.id}")
      # ...and submitted orders render as plain table rows.
      expect(response.body).to include("<td>#{submitted.id}</td>")
    end

    it "shows the Admin Page affordance for staff" do
      http_login!(staff)
      get job_orders_path
      expect(response.body).to include(I18n.t("job_orders.public_page.admin_page"))
    end
  end

  # ------------------------------------------------------- GET show

  describe "GET /job_orders/:id (show)" do
    it "renders the Job Order heading for the owner" do
      order = order_with_task!(owner: owner)
      http_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Order ##{order.id}")
      expect(response.body).to include(owner.name)
      expect(response.body).to include("Task #1")
    end

    it "marks the owner's unread chat messages as read" do
      order = order_with_task!(owner: owner)
      ChatMessage.create!(job_order: order, sender: staff, message: "quote stuff")
      unread = order.chat_messages.first
      expect(unread.is_read).to be(false)

      http_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(unread.reload.is_read).to be(true)
    end

    it "does NOT mark messages read for non-owner viewers (staff)" do
      order = order_with_task!(owner: owner)
      ChatMessage.create!(job_order: order, sender: staff, message: "hi")
      seed_job_types!
      order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
      http_login!(staff)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(order.chat_messages.first.reload.is_read).to be(false)
    end

    # FIXED(D-J06): show is limited to the owner, staff and admin
    it "refuses another regular user (no_permission redirect, no owner email)" do
      order = order_with_task!(owner: owner)
      http_login!(other)
      get job_order_path(order)
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
      expect(response.body).not_to include(owner.email)
    end

    it "renders the order, with the owner's email, to staff and admin" do
      order = order_with_task!(owner: owner)
      seed_job_types!
      order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
      [staff, admin].each do |viewer|
        http_login!(viewer)
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(owner.email)
      end
    end

    it "shows the action-required notice to an owner under USER_APPROVAL" do
      order = order_with_task!(owner: owner)
      advance_to!(order, :user_approval)
      http_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(flash[:notice])
        .to eq(I18n.t("job_orders.alerts.action_required_scroll_to_timeline"))
    end

    it "alerts when tasks are missing required information" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      order.job_tasks.create!(title: "Task #1")
      http_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert])
        .to eq("#{I18n.t('job_orders.alerts.missing_info')} Task #1")
    end

    # WART(D-J13): the Submit-for-Approval button_to resolves
    # job_order_job_task_path with @job_order.job_tasks.first == nil →
    # UrlGenerationError → 500.
    it "renders 500 (UrlGenerationError) for a DRAFT order with no tasks" do
      order = make_job_order!(owner: owner, status_key: :draft)
      http_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Action Controller: Exception caught")
      expect(response.body).to include("UrlGenerationError")
    end

    # WART(D-J14): @message is dereferenced BEFORE the nil check, so the
    # "job order not found" flash/redirect branch is dead code.
    it "renders 500 (NoMethodError) for a missing or deleted order" do
      order = order_with_task!(owner: owner)
      http_login!(owner)

      get job_order_path(id: 999_999_999)
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("NoMethodError")

      order.update!(is_deleted: true)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("NoMethodError")
    end
  end

  # ------------------------------------------------------- POST create

  describe "POST /job_orders (create)" do
    before do
      # The Design-Services flow resolves JobType by name (seeded by the
      # migration data in any deployed DB).
      seed_job_types!
      http_login!(owner)
    end

    it "creates a Draft order + first task and redirects to the wizard step 1" do
      post job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "1" }

      order = JobOrder.order(:id).last
      expect(response).to redirect_to(
        edit_job_order_job_task_path(order, order.job_tasks.first, step: 1)
      )
      expect(order.user).to eq(owner)
      expect(order.job_order_statuses.order(:id).map { |s| s.job_status&.name }).to eq(["Draft"])
      expect(order.job_order_statuses.last.user).to eq(owner)
      expect(order.job_tasks.first.title).to eq("Task #1")
      expect(order.job_tasks.first.job_type).to be_nil
    end

    it "forces the Design Services job type when redirect_step=2" do
      post job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "2" }

      order = JobOrder.order(:id).last
      task = order.job_tasks.first
      expect(response).to redirect_to(edit_job_order_job_task_path(order, task, step: 1))
      expect(task.job_type.name).to eq("Design Services")
    end

    it "still creates one order and one task with an unknown redirect_step" do
      expect do
        post job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "99" }
      end.to change(JobOrder, :count).by(1).and change(JobTask, :count).by(1)
      expect(JobOrder.order(:id).last.job_tasks.first.job_type).to be_nil
    end

    it "redirects to root with the raw parameter_missing message when job_order param is absent" do
      post job_orders_path, params: { other: "x" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert])
        .to eq("param is missing or the value is empty or invalid: job_order")
    end

    it "POST /job_orders/new is wired to #new in the routes (renders the choice page, does not create)" do
      post new_job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "1" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("job_orders.new.title"))
      expect(JobOrder.count).to eq(0)
    end
  end

  # ------------------------------------------------------- GET new

  describe "GET /job_orders/new" do
    it "renders the two entry cards and the hidden redirect_step fields" do
      http_login!(owner)
      get new_job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("job_orders.new.ready_to_make.title"))
      expect(response.body).to include(I18n.t("job_orders.new.need_design_help.title"))
      expect(response.body).to include('name="job_order[job_type_id]"')
      expect(response.body).to include('name="redirect_step"')
    end
  end

  # ------------------------------------------------------- GET landing

  describe "GET /job_orders/landing" do
    it "is reachable without sign-in and keeps the global nav" do
      get landing_job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("job_orders.header"))
      expect(response.body).to include(I18n.t("job_orders.request_button"))
      expect(response.body).to include(I18n.t("job_orders.view_orders_button"))
      expect(response.body).to include('<nav class="navbar')
      expect(response.body).to include("Sign In | Register")
    end
  end

  # ------------------------------------------------------- DELETE destroy

  describe "DELETE /job_orders/:id (destroy)" do
    it "soft-deletes (is_deleted = true), redirects to the client index with a flash" do
      order = order_with_task!(owner: owner)
      http_login!(owner)
      delete job_order_path(order)
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:notice]).to eq("Job order deleted successfully.")
      expect(order.reload.is_deleted).to be(true)
      expect(JobOrder.where(id: order.id, is_deleted: false)).to be_empty
    end

    it "sends the admin back to the admin index" do
      order = order_with_task!(owner: owner)
      http_login!(admin)
      delete job_order_path(order)
      expect(response).to redirect_to(admin_job_orders_path)
      expect(order.reload.is_deleted).to be(true)
    end

    it "blocks non-owners with the no_permission flash and redirect (soft delete prevented)" do
      order = order_with_task!(owner: owner)
      http_login!(other)
      delete job_order_path(order)
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
      expect(order.reload.is_deleted).to be(false)
    end
  end

  # ------------------------------------------------------- PATCH user_approval

  describe "PATCH /job_orders/:id/user_approval" do
    it "moves USER_APPROVAL → WAITING_PROCESSED, notifies staff by mail, redirects (HTML)" do
      order = order_with_task!(owner: owner)
      advance_to!(order, :user_approval)
      http_login!(owner)
      expect do
        patch job_order_user_approval_path(order), params: { approved: "true" }
      end.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to(job_order_path(order))
      expect(status_names(order))
        .to eq(["Draft", "Waiting for User Approval", "Waiting to be Processed"])
      expect(ActionMailer::Base.deliveries.last.subject)
        .to eq("A user has approved a Job Order")
      expect(ActionMailer::Base.deliveries.last.to).to eq(["makerspace@uottawa.ca"])
    end

    it "APPROVED=false records the DECLINED status without a mail" do
      order = order_with_task!(owner: owner)
      advance_to!(order, :user_approval)
      http_login!(owner)
      expect do
        patch job_order_user_approval_path(order), params: { approved: "false" }
      end.not_to(change { ActionMailer::Base.deliveries.size })

      expect(status_names(order)).to include("Declined")
      expect(status_names(order)).not_to include("Waiting to be Processed")
    end

    it "alerts and does nothing for a non-matching current state" do
      order = order_with_task!(owner: owner) # Draft
      http_login!(owner)
      expect do
        patch job_order_user_approval_path(order), params: { approved: "true" }
      end.not_to change(JobOrderStatus, :count)
      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
    end

    # WART(D-J15): format.js renders admin_row but points at _assign_staff,
    # which dereferences @staff (nil outside the admin page) → Template::Error
    # → 500.
    it "responds 500 (ActionView::Template::Error, HTML debug page) to format.js on row actions" do
      order = order_with_task!(owner: owner)
      advance_to!(order, :user_approval)
      http_login!(owner)
      patch job_order_user_approval_path(order),
            params: { approved: "true" },
            headers: { "ACCEPT" => "text/javascript" }

      expect(response).to have_http_status(:internal_server_error)
      expect(response.headers["Content-Type"]).to start_with("text/html")
      expect(response.body).to include("Action Controller: Exception caught")
      expect(response.body).to include("ActionView::Template::Error")
    end
  end

  # ------------------------------------------------------- PATCH quote

  describe "PATCH /job_orders/:id/quote" do
    let(:order) { order_with_task!(owner: owner, status_key: :staff_approval) }

    def quote_params(order, task)
      {
        approved: "true",
        "job_task_quote_price_#{task.id}" => "124.5",
        "task_#{task.id}_service_qty" => "2",
        "task_#{task.id}_service_price" => "3",
        job_order: { staff_comments: "use the big printer" },
        user_comments: "I will add supports myself"
      }
    end

    it "requires staff/admin (a regular user is bounced to root)" do
      http_login!(owner)
      patch job_order_quote_path(order), params: quote_params(order, order.job_tasks.first)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.cannot_access_area"))
    end

    context "as staff" do
      before { http_login!(staff) }

      it "saves task quote, staff comments, chat message, sets USER_APPROVAL and emails the quote" do
        task = order.job_tasks.first
        expect do
          patch job_order_quote_path(order), params: quote_params(order, task)
        end.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(response).to redirect_to(job_order_path(order))
        expect(flash[:notice])
          .to eq(I18n.t("job_orders.alerts.updated_job_status_to_x",
                        status: "Waiting for User Approval"))

        expect(task.reload.job_task_quote.price).to eq(124.5)
        expect(task.reload.job_task_quote.service_quantity).to eq(2)
        expect(task.reload.job_task_quote.service_price).to eq(3)
        expect(order.reload.staff_comments).to eq("use the big printer")
        expect(order.reload.chat_messages.last.message).to eq("I will add supports myself")
        expect(order.reload.chat_messages.last.sender).to eq(staff)
        expect(status_names(order))
          .to eq(["Waiting for Staff Approval", "Waiting for User Approval"])
        expect(order.job_order_statuses.last.user).to eq(staff)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject)
          .to eq("Votre commande ##{order.id} a été approuvée // Your job order ##{order.id} has been approved")
        expect(mail.to).to eq([order.user.email])
        expect(mail.bcc).to eq(["uottawa.makerepo@gmail.com"])
        expect(mail.reply_to).to eq(["makerspace@uottawa.ca"])
        # The mailer embeds a signed magic-approval token for the order
        expect(mail.body.encoded).to include("user_magic_approval?token=")
      end

      it "switches to the re-approved wording after a second quote submission" do
        task = order.job_tasks.first
        patch job_order_quote_path(order), params: quote_params(order, task)
        patch job_order_quote_path(order), params: quote_params(order, task)

        second = ActionMailer::Base.deliveries.last
        expect(second.subject)
          .to eq("Votre commande ##{order.id} a été réapprouvée // Your job order ##{order.id} has been re-approved")
      end

      it "attaches staff files and prefixes stored filenames with the order id" do
        task = order.job_tasks.first
        patch job_order_quote_path(order), params: quote_params(order, task).merge(
          "task_#{task.id}_staff_files" => [FilesTestHelper.stl]
        )
        task.reload
        expect(task.staff_files.count).to eq(1)
        expect(task.staff_files.first.filename.to_s)
          .to eq("#{order.id}_#{FilesTestHelper.stl_name}")
      end

      it "replaces job quote line items from submitted params" do
        order.job_quote_line_items.create!(description: "old", price: 1)
        task = order.job_tasks.first
        patch job_order_quote_path(order), params: quote_params(order, task).merge(
          job_quote_line_items: {
            "0" => { description: "Expedited SLA resin", price: "12.5" },
            "1" => { description: "", price: "" }
          }
        )
        expect(order.reload.job_quote_line_items.pluck(:description, :price))
          .to contain_exactly(["Expedited SLA resin", BigDecimal("12.5")])
      end

      it "declines: sets DECLINED, emails the user, no USER_APPROVAL status" do
        task = order.job_tasks.first
        expect do
          patch job_order_quote_path(order),
                params: quote_params(order, task).merge(approved: "false")
        end.to change { ActionMailer::Base.deliveries.size }.by(1)

        expect(status_names(order)).to end_with("Declined")
        expect(ActionMailer::Base.deliveries.last.subject)
          .to eq("Your job ##{order.id} has been declined")
        expect(ActionMailer::Base.deliveries.last.to).to eq([order.user.email])
        expect(flash[:notice])
          .to eq(I18n.t("job_orders.alerts.updated_job_status_to_x", status: "Declined"))
      end

      it "blank approved just flashes the error and renders nothing (204)" do
        task = order.job_tasks.first
        patch job_order_quote_path(order),
              params: quote_params(order, task).merge(approved: "")
        expect(response.status).to eq(204)
        expect(response.body).to be_blank
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
        expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      end
    end
  end

  # ------------------------------------------------------- PATCH comments

  describe "PATCH /job_orders/:id/comments" do
    it "lets staff persist comment fields and redirects with a notice" do
      order = order_with_task!(owner: owner)
      http_login!(staff)
      patch job_order_comments_path(order),
            params: { job_order: { staff_comments: "annotated on the staff panel" } }

      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:notice]).to eq(I18n.t("job_orders.alerts.updated_successfully"))
      expect(order.reload.staff_comments).to eq("annotated on the staff panel")
    end

    it "bounces regular users (grant_access) to root" do
      order = order_with_task!(owner: owner)
      http_login!(owner)
      patch job_order_comments_path(order),
            params: { job_order: { staff_comments: "sneaky" } }
      expect(response).to redirect_to(root_path)
      expect(order.reload.staff_comments).not_to eq("sneaky")
    end
  end

  # ------------------------------------------------------- Staff transitions

  # Each PATCH transition seeds the order at `from` (single status row — the
  # row history starts there; no implicit "Draft" entry exists).
  transitions = {
    start_processing: {
      ok_param: "start_processing",
      from: :waiting_processed, final: :being_processed,
      chain: ["Waiting to be Processed", "Currently being Processed"]
    },
    paid: {
      ok_param: "paid",
      from: :completed, final: :paid,
      chain: ["Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)"]
    },
    picked_up: {
      ok_param: "picked_up",
      from: :paid, final: :picked_up,
      chain: ["Paid (Waiting for Pick-Up)", "Picked-Up"]
    },
    # `processed` is not in the controller's own list of simple transitions (it
    # also branches on price and mail), but it shares the guard rails. A priced
    # order is prepared so the zero-price auto-pay branch stays out of the way.
    processed: {
      ok_param: "completed",
      from: :being_processed, final: :completed,
      chain: ["Currently being Processed", "Completed (Waiting for Payment)"],
      prepare: ->(order) { order.job_tasks.first.build_job_task_quote(price: 10).save! }
    }
  }.freeze

  transitions.each do |action, flow|
    describe "PATCH /job_orders/:id/#{action}" do
      it "rejects guests with the login?back_to redirect" do
        order = order_with_task!(owner: owner)
        patch send("job_order_#{action}_path", order),
              params: { flow.fetch(:ok_param) => "true" }
        expect(response)
          .to redirect_to(login_path)
      end

      it "rejects regular users to root with cannot_access_area" do
        order = order_with_task!(owner: owner)
        http_login!(owner)
        patch send("job_order_#{action}_path", order),
              params: { flow.fetch(:ok_param) => "true" }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.cannot_access_area"))
      end

      context "as staff" do
        before { http_login!(staff) }

        it "advances when the current status allows it" do
          order = order_with_task!(owner: owner, status_key: flow.fetch(:from))
          flow[:prepare]&.call(order)
          patch send("job_order_#{action}_path", order),
                params: { flow.fetch(:ok_param) => "true" }

          expect(response).to redirect_to(job_order_path(order))
          expect(flash[:notice])
            .to eq(I18n.t("job_orders.alerts.updated_job_status_to_x",
                          status: JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(flow.fetch(:final))))
          expect(status_names(order)).to eq(flow.fetch(:chain))
        end

        it "records nothing when the param is false (and flashes the update error)" do
          order = order_with_task!(owner: owner, status_key: flow.fetch(:from))
          patch send("job_order_#{action}_path", order),
                params: { flow.fetch(:ok_param) => "false" }

          expect(status_names(order)).to eq([JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(flow.fetch(:from))])
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
        end

        # WART(D-J16): applying #{action} to a Draft flashes the generic update
        # error; no guard rail explains WHY the transition was refused.
        it "errors from an unexpected current status" do
          order = order_with_task!(owner: owner, status_key: :draft)
          expect do
            patch send("job_order_#{action}_path", order),
                  params: { flow.fetch(:ok_param) => "true" }
          end.not_to change(JobOrderStatus, :count)
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
        end
      end
    end
  end

  describe "PATCH /job_orders/:id/processed special predicates" do
    before { http_login!(staff) }

    it "auto-pays (Paid status + payment_succeeded mail) when total_price is 0" do
      order = order_with_task!(owner: owner, status_key: :being_processed)
      order.job_tasks.first.build_job_task_quote(price: 0).save!
      expect(order.total_price).to eq(0)

      patch job_order_processed_path(order), params: { completed: "true" }
      expect(response).to redirect_to(job_order_path(order))
      expect(status_names(order)).to eq(
        ["Currently being Processed", "Completed (Waiting for Payment)",
         "Paid (Waiting for Pick-Up)"]
      )
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Your Job Order ##{order.id} is now ready for pickup")
      expect(mail.to).to eq([owner.email])
    end

    it "emails the completion message when send_email=true (a priced order skips the auto-pay branch)" do
      order = order_with_task!(owner: owner, status_key: :being_processed)
      order.job_tasks.first.build_job_task_quote(price: 10).save!

      patch job_order_processed_path(order),
            params: { completed: "true", send_email: "true", message: "<p>Your part is done.</p>" }
      expect(response).to redirect_to(job_order_path(order))
      expect(status_names(order)).to end_with("Completed (Waiting for Payment)")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.subject)
        .to eq("Your Job Order ##{order.id} has been completed")
      expect(ActionMailer::Base.deliveries.last.to).to eq([owner.email])
      expect(ActionMailer::Base.deliveries.last.body.encoded).to include("Your part is done.")
    end

    it "creates no mail without send_email on a priced order" do
      order = order_with_task!(owner: owner, status_key: :being_processed)
      order.job_tasks.first.build_job_task_quote(price: 10).save!
      expect do
        patch job_order_processed_path(order), params: { completed: "true" }
      end.not_to(change { ActionMailer::Base.deliveries.size })
      expect(status_names(order)).to end_with("Completed (Waiting for Payment)")
    end
  end

  # ------------------------------------------------------- resend_quote_email

  # The mailer picks the first-approval ("approuvée/approved") or renewed
  # ("réapprouvée/re-approved") wording by counting the order's USER_APPROVAL
  # history rows (>1) — the `reminder` argument it receives is ignored for
  # wording purposes.
  describe "PATCH /job_orders/:id/resend_quote_email" do
    before { http_login!(staff) }

    it "records Sent a Quote Reminder and re-delivers the quote mail" do
      order = order_with_task!(owner: owner, status_key: :user_approval)
      expect do
        patch job_order_resend_quote_email_path(order)
      end.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to(job_order_path(order))
      expect(status_names(order)).to end_with("Sent a Quote Reminder")
      expect(ActionMailer::Base.deliveries.last.subject)
        .to eq("Votre commande ##{order.id} a été approuvée // Your job order ##{order.id} has been approved")
      expect(ActionMailer::Base.deliveries.last.to).to eq([order.user.email])
      # the reminder flag adds the reminder paragraph (English + French)
      expect(ActionMailer::Base.deliveries.last.body.encoded)
        .to include("This is a reminder that admins have approved a Job Order.")
    end

    it "uses the re-approved wording once the order has multiple USER_APPROVAL rows" do
      order = order_with_task!(owner: owner, status_key: :user_approval)
      advance_to!(order, :user_approval)
      expect(order.job_order_statuses.where(job_status: JobStatus.user_approval).count).to eq(2)

      patch job_order_resend_quote_email_path(order)
      expect(ActionMailer::Base.deliveries.last.subject)
        .to eq("Votre commande ##{order.id} a été réapprouvée // Your job order ##{order.id} has been re-approved")
    end
  end

  # ------------------------------------------------------- assign_staff

  describe "PATCH /job_orders/:id/assign_staff" do
    it "lets an admin assign a staff member and delivers the staff_assigned mail to them" do
      order = order_with_task!(owner: owner)
      http_login!(admin)
      perform_enqueued_jobs do
        patch job_order_assign_staff_path(order), params: { staff_id: staff.id }
      end

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([staff.email])
      expect(mail.subject).to eq("You've been assigned to Job Order ##{order.id}")
      expect(response).to redirect_to(job_orders_path) # redirect_back fallback
      expect(flash[:notice]).to eq("#{staff.name} has been assigned to this job order.")
      expect(order.reload.assigned_staff).to eq(staff)
    end

    it "does NOT email when the admin assigns themselves" do
      order = order_with_task!(owner: owner)
      http_login!(admin)
      perform_enqueued_jobs do
        patch job_order_assign_staff_path(order), params: { staff_id: admin.id }
      end
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(order.reload.assigned_staff).to eq(admin)
      expect(flash[:notice]).to eq("#{admin.name} has been assigned to this job order.")
    end

    # FIXED(D-J07): assign_staff goes through grant_access (staff/admin only)
    it "refuses a regular user self-assigning (staff_id == own id)" do
      order = order_with_task!(owner: owner)
      http_login!(other)
      perform_enqueued_jobs do
        patch job_order_assign_staff_path(order), params: { staff_id: other.id }
      end
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.cannot_access_area"))
      expect(order.reload.assigned_staff).to be_nil
    end

    it "redirects a guest to login and assigns nobody" do
      order = order_with_task!(owner: owner)
      patch job_order_assign_staff_path(order), params: { staff_id: other.id }
      expect(response).to have_http_status(:redirect)
      expect(order.reload.assigned_staff).to be_nil
    end

    it "staff can claim a job themselves (Assign Me button path) with no mail" do
      order = order_with_task!(owner: owner)
      http_login!(staff)
      perform_enqueued_jobs do
        patch job_order_assign_staff_path(order), params: { staff_id: staff.id }
      end
      expect(order.reload.assigned_staff).to eq(staff)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    # WART(D-J08): the else-flash dereferences @job_order.assigned_staff.name
    # with no assigned staff → NoMethodError → 500 instead of a friendly flash.
    it "renders 500 (NoMethodError) when a non-admin staff member tries to assign someone else" do
      order = order_with_task!(owner: owner)
      http_login!(staff)
      patch job_order_assign_staff_path(order), params: { staff_id: admin.id }
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("NoMethodError")
      expect(order.reload.assigned_staff).to be_nil
    end

    # WART(D-J08): an unknown job order takes the same else branch,
    # @job_order is nil. (The route's key is job_order_id.)
    it "renders 500 (NoMethodError) for an unknown job order id" do
      http_login!(staff)
      patch job_order_assign_staff_path(job_order_id: 999_999_999),
            params: { staff_id: staff.id }
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("NoMethodError")
    end
  end

  # ------------------------------------------------------- admin / settings

  describe "GET /job_orders/admin" do
    # N+1 pinned: see defects.md D-PERF02
    it "lists non-draft orders for staff and keeps the drafts out (no # anchor markers)", skip_bullet: true do
      draft = make_job_order!(owner: owner, status_key: :draft)
      listed = order_with_task!(owner: owner, status_key: :staff_approval)

      http_login!(staff)
      get admin_job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("All Job Orders")
      # The admin table prints the id as a bare <td>, not "Order #N".
      expect(response.body).to include("<td>#{listed.id}</td>")
      expect(response.body).not_to include("<td>#{draft.id}</td>")
    end

    it "bounces regular users to root" do
      http_login!(owner)
      get admin_job_orders_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.cannot_access_area"))
    end
  end

  describe "GET /job_orders/settings" do
    it "renders the admin settings page for staff" do
      http_login!(staff)
      get settings_job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Orders Settings")
    end

    it "bounces regular users to root" do
      http_login!(owner)
      get settings_job_orders_path
      expect(response).to redirect_to(root_path)
    end
  end

  # ------------------------------------------------------- invoice

  describe "GET /job_orders/:id/invoice" do
    it "renders a printable (layout-free) invoice for the owner" do
      order = order_with_task!(owner: owner, status_key: :completed)
      order.job_tasks.first.build_job_task_quote(price: 42, service_price: 0, service_quantity: 0).save!
      http_login!(owner)
      get job_order_invoice_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Invoice ##{order.id}")
      expect(response.body).to include("Task #1 - Base Fee")
      expect(response.body).to match(/Total: CAD \$42\.00/)
      expect(response.body).not_to include("nav.navbar") # layout: false
    end

    it "serves staff as well" do
      order = order_with_task!(owner: owner)
      http_login!(staff)
      get job_order_invoice_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Invoice ##{order.id}")
    end

    it "redirects unrelated users to new_job_orders_path with no_permission" do
      order = order_with_task!(owner: owner)
      http_login!(other)
      get job_order_invoice_path(order)
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
    end
  end

  # ------------------------------------------------------- timeline modal

  describe "GET /job_orders/:id/timeline_modal" do
    # N+1 pinned: see defects.md D-PERF03
    it "renders the status history (layout: false) newest-first for staff", skip_bullet: true do
      order = order_with_task!(owner: owner)
      advance_to!(order, :staff_approval)
      http_login!(staff)
      get job_order_timeline_modal_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="timeline-modal-rendered"')
      expect(response.body).to match(/Waiting for Staff Approval.*?Draft/m)
      expect(response.body).not_to include("nav.navbar") # layout: false
    end

    # JOB-01 review 7: JobOrderStatus#user is optional (rows from before its presence validation have none)
    it "names a missing actor 'Unknown' instead of raising, on processing and sent-back rows", skip_bullet: true do
      order = order_with_task!(owner: owner)
      advance_to!(order, :being_processed)
      sent_back = order.job_order_statuses.create!(job_status: JobStatus.staff_approval, user: owner, reason: "owner_change")
      JobOrderStatus.where(id: [sent_back.id, order.job_order_statuses.find_by!(job_status: JobStatus.being_processed).id])
                    .update_all(user_id: nil)
      http_login!(staff)
      get job_order_timeline_modal_path(order)

      expect(response).to have_http_status(:ok)
      text = Nokogiri::HTML(response.body).text.squish
      expect(text).to include("Currently being Processed (By: Unknown)")
      expect(text).to include("#{I18n.t('job_orders.status_reasons.owner_change')} (By: Unknown)")
    end

    # Round 2 review 9: no N+1 (runs with Bullet on): statuses and their JobStatus in one query, users only for the
    # rows that name their actor, in one query
    it "loads the history with a fixed number of queries, users only for rows that show them" do
      order = order_with_task!(owner: owner)
      %i[staff_approval user_approval waiting_processed being_processed completed].each { |k| advance_to!(order, k) }
      order.job_order_statuses.create!(job_status: JobStatus.staff_approval, user: owner, reason: "owner_change")
      http_login!(staff)
      JobStatus::STATUS_NAMES.each_key { |key| JobStatus.public_send(key) } # the per-process lookups are warm in a running app
      tables = Hash.new(0)
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        %w[job_order_statuses job_statuses users].each { |t| tables[t] += 1 if payload[:sql].match?(/FROM "#{t}"/) }
      end
      begin
        get job_order_timeline_modal_path(order)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      text = Nokogiri::HTML(response.body).text.squish
      expect(text).to include("Currently being Processed (By: #{owner.name})")
      expect(text).to include("#{I18n.t('job_orders.status_reasons.owner_change')} (By: #{owner.name})")
      expect(tables["job_order_statuses"]).to eq(1)
      expect(tables["job_statuses"]).to eq(1)
      expect(tables["users"]).to be <= 2 # the signed-in staff user, and the actors of the rows that show them
    end

    it "is staff/admin only — the owner gets bounced to root" do
      order = order_with_task!(owner: owner)
      http_login!(owner)
      get job_order_timeline_modal_path(order)
      expect(response).to redirect_to(root_path)
    end
  end

  # ------------------------------------------------------- removed dead routes

  # D-J17 / D-CRAWL04: these routes pointed at missing templates or actions and
  # were removed. Every verb now answers 404 for every role.
  describe "removed dead routes" do
    {
      "GET quote_modal" => ->(id) { [:get, "/job_orders/#{id}/quote_modal"] },
      "GET decline_modal" => ->(id) { [:get, "/job_orders/#{id}/decline_modal"] },
      "GET comments_modal" => ->(id) { [:get, "/job_orders/#{id}/comments_modal"] },
      "GET completed_email_modal" => ->(id) { [:get, "/job_orders/#{id}/completed_email_modal"] },
      "GET steps" => ->(id) { [:get, "/job_orders/#{id}/steps"] },
      "PATCH steps" => ->(id) { [:patch, "/job_orders/#{id}/steps"] },
      "GET edit" => ->(id) { [:get, "/job_orders/#{id}/edit"] },
      "PATCH update" => ->(id) { [:patch, "/job_orders/#{id}"] },
      "PUT update" => ->(id) { [:put, "/job_orders/#{id}"] }
    }.each do |name, build|
      it "answers 404 for #{name} as staff" do
        order = order_with_task!(owner: owner)
        http_login!(staff)
        verb, path = build.call(order.id)
        public_send(verb, path, params: { job_order: { comments: "x" } })
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ------------------------------------------------------- magic link approval

  describe "magic-link user approval" do
    let(:magic_order) { order_with_task!(owner: owner, status_key: :user_approval) }
    let(:token) { magic_link_token_for(magic_order) }

    describe "GET /job_orders/user_magic_approval" do
      it "renders the guest approval page with quote total and approve/deny buttons" do
        get user_magic_approval_job_orders_path, params: { token: token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Thank You for ordering a Job Order!")
        expect(response.body).to include("Total Quote:")
        expect(response.body).to include("Approve the Quote")
        expect(response.body).to include("Deny the Quote")
        expect(response.body).to include("user_magic_approval_confirmation")
      end

      it "rejects a valid token for an order without any status instead of raising" do
        JobOrderStatus.where(job_order_id: magic_order.id).delete_all
        get user_magic_approval_job_orders_path, params: { token: token }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert])
          .to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
      end

      it "rejects tampered tokens with the expired-flash redirect" do
        get user_magic_approval_job_orders_path,
            params: { token: token.sub(/.\z/, "X") }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert])
          .to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
      end

      it "rejects valid tokens for orders not awaiting user approval (Draft)" do
        draft = order_with_task!(owner: owner, status_key: :draft)
        get user_magic_approval_job_orders_path,
            params: { token: magic_link_token_for(draft) }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert])
          .to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
      end

      it "rejects valid tokens for soft-deleted orders" do
        magic_order.update!(is_deleted: true)
        get user_magic_approval_job_orders_path, params: { token: token }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert])
          .to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
      end

      # FIXED(D-J11): approval links expire after 14 days. The order and token
      # are minted NOW, before any time travel.
      it "accepts a token for 14 days and refuses it afterwards" do
        minted = token
        travel_to(13.days.from_now) do
          get user_magic_approval_job_orders_path, params: { token: minted }
          expect(response).to have_http_status(:ok)
        end
        travel_to(15.days.from_now) do
          get user_magic_approval_job_orders_path, params: { token: minted }
          expect(response).to redirect_to(job_orders_path)
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
        end
      end

      it "refuses an expired token on the confirmation too, changing nothing" do
        minted = token
        travel_to(15.days.from_now) do
          patch user_magic_approval_confirmation_job_orders_path, params: { token: minted, approved: "true" }
        end
        expect(response).to redirect_to(job_orders_path)
        expect(status_names(magic_order)).to eq(["Waiting for User Approval"])
      end

      it "refuses a pay token (separate purpose) and a pre-D-J11 legacy token" do
        [magic_pay_token_for(magic_order),
         Rails.application.message_verifier(:job_order_id).generate(magic_order.id)].each do |bad|
          get user_magic_approval_job_orders_path, params: { token: bad }
          expect(response).to redirect_to(job_orders_path)
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))
          patch user_magic_approval_confirmation_job_orders_path, params: { token: bad, approved: "true" }
          expect(response).to redirect_to(job_orders_path)
        end
        expect(status_names(magic_order)).to eq(["Waiting for User Approval"])
      end

      it "refuses a token whose owner no longer matches the order" do
        minted = token
        magic_order.update_columns(user_id: create(:user, :regular_user).id)
        get user_magic_approval_job_orders_path, params: { token: minted }
        expect(response).to redirect_to(job_orders_path)
      end

      it "a link for another order does not open this one" do
        other_order = order_with_task!(owner: owner, status_key: :user_approval)
        patch user_magic_approval_confirmation_job_orders_path, params: { token: magic_link_token_for(other_order), approved: "true" }
        expect(status_names(magic_order)).to eq(["Waiting for User Approval"])
        expect(status_names(other_order)).to end_with("Waiting to be Processed")
      end

      it "a link from before a re-quote is retired when the order gets a new approval round" do
        old = token
        magic_order.job_order_statuses.create!(job_status: JobStatus.user_approval, user: owner)
        get user_magic_approval_job_orders_path, params: { token: old }
        expect(response).to redirect_to(job_orders_path)
        get user_magic_approval_job_orders_path, params: { token: magic_order.reload.approval_token }
        expect(response).to have_http_status(:ok)
      end

      it "a reminder keeps the original link working" do
        old = token
        magic_order.job_order_statuses.create!(job_status: JobStatus.sent_reminder, user: owner)
        get user_magic_approval_job_orders_path, params: { token: old }
        expect(response).to have_http_status(:ok)
      end

      it "the link is spent once the order has been approved" do
        patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }
        get user_magic_approval_job_orders_path, params: { token: token }
        expect(response).to redirect_to(job_orders_path)
      end
    end

    describe "PATCH /job_orders/user_magic_approval_confirmation" do
      it "rejects invalid tokens with the accept/deny error flash and changes nothing" do
        patch user_magic_approval_confirmation_job_orders_path,
              params: { token: "not-a-token", approved: "true" }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert])
          .to eq(I18n.t("job_orders.alerts.error_accept_deny_order"))
        expect(status_names(magic_order)).not_to include("Waiting to be Processed")
      end

      context "with a signed user session (the already-logged-in browser case)" do
        before { http_login!(owner) }

        it "approves: renders the confirmation page and appends Waiting to be Processed" do
          patch user_magic_approval_confirmation_job_orders_path,
                params: { token: token, approved: "true" }
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Thank You for Approving/Denying the Job Order!")
          expect(status_names(magic_order))
            .to eq(["Waiting for User Approval", "Waiting to be Processed"])
          expect(magic_order.job_order_statuses.last.user).to eq(owner)
          # WART(D-J37): the magic-link path notifies nobody
          expect(ActionMailer::Base.deliveries).to be_empty
        end

        it "denies: appends Declined" do
          patch user_magic_approval_confirmation_job_orders_path,
                params: { token: token, approved: "false" }
          expect(response).to have_http_status(:ok)
          expect(status_names(magic_order)).to end_with("Declined")
          expect(status_names(magic_order)).not_to include("Waiting to be Processed")
        end

        # The status check is the only "one-time" guard: the token itself stays
        # valid; replaying renders the guarded (non-updated) response.
        it "replays a spent token: error page, status untouched" do
          patch user_magic_approval_confirmation_job_orders_path,
                params: { token: token, approved: "true" }
          expect(response.body).to include("Thank You for Approving/Denying the Job Order!")
          count = JobOrderStatus.count
          patch user_magic_approval_confirmation_job_orders_path,
                params: { token: token, approved: "true" }
          expect(response).to have_http_status(:ok)
          expect(response.body)
            .to include("An error occured while trying to Approve/Deny the Job Order...")
          expect(JobOrderStatus.count).to eq(count)
          expect(status_names(magic_order)).to end_with("Waiting to be Processed")
        end
      end

      # FIXED(D-J09): the status row is attributed to the order's owner, so a
      # guest following the emailed link can approve or deny without signing in.
      it "lets an anonymous visitor approve: the status is persisted and attributed to the order owner" do
        patch user_magic_approval_confirmation_job_orders_path,
              params: { token: token, approved: "true" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Thank You for Approving/Denying the Job Order!")
        expect(status_names(magic_order)).to eq(["Waiting for User Approval", "Waiting to be Processed"])
        expect(magic_order.job_order_statuses.last.user).to eq(owner)
      end

      it "lets an anonymous visitor deny: Declined, attributed to the owner" do
        patch user_magic_approval_confirmation_job_orders_path,
              params: { token: token, approved: "false" }
        expect(status_names(magic_order)).to end_with("Declined")
        expect(magic_order.job_order_statuses.last.user).to eq(owner)
      end

      it "an anonymous replay of a spent link records nothing more" do
        2.times do
          patch user_magic_approval_confirmation_job_orders_path,
                params: { token: token, approved: "true" }
        end
        expect(response.body).to include("An error occured while trying to Approve/Deny the Job Order...")
        expect(status_names(magic_order)).to eq(["Waiting for User Approval", "Waiting to be Processed"])
      end

      it "refuses a token that is not a signed approval token" do
        broken = "not-a-token"
        patch user_magic_approval_confirmation_job_orders_path,
              params: { token: broken, approved: "true" }
        expect(response).to redirect_to(job_orders_path)
      end
    end
  end

  # ------------------------------------------------------- pay (magic payment)

  describe "GET /job_orders/pay" do
    # The Shopify GraphQL client is the boundary (no sockets): the first visit
    # creates the draft order, then fetches its invoice URL.
    let!(:shopify) do
      stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/inv" }
    end

    it "renders the payment-link page for a valid token on a COMPLETED order" do
      order = order_with_task!(owner: owner, status_key: :completed)
      # the quote action always writes service_price/quantity (0.0 when blank)
      order.job_tasks.first.build_job_task_quote(
        price: 29.99, service_price: 0, service_quantity: 0
      ).save!

      get pay_job_orders_path, params: { token: magic_pay_token_for(order) }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Proceed to the payment page")
      expect(response.body).to include("https://pay.example/inv")
      expect(response.body).to include("Total Quote:")
      # WART(D-J38): the draft order is created on a GET and only fetched later
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")
      # FIXED(D-J50): the view reuses the controller's @payment_link, so a visit
      # is just create + the fetch inside create (no redundant second fetch).
      expect(shopify.calls.map { |c| c[:query][/\b(draftOrderCreate|getDraftOrder)\b/] })
        .to eq(%w[draftOrderCreate getDraftOrder])
      line_items = shopify.calls.first[:variables][:input][:lineItems]
      expect(line_items.map { |li| li[:title] })
        .to eq(["Task #1 Service Fee", "Line Items Total"])
      expect(line_items.first[:originalUnitPriceWithCurrency])
        .to eq(amount: BigDecimal("29.99"), currencyCode: "CAD")
    end

    # FIXED(D-J12, as a side effect of the token lookup now returning the order):
    # a valid token on a non-COMPLETED order used to 500 on a nil @job_order; it
    # now redirects to the order page (login for a guest) with the pay flash.
    it "redirects with the pay flash for a valid token on a non-COMPLETED order" do
      order = order_with_task!(owner: owner, status_key: :user_approval)
      get pay_job_orders_path, params: { token: magic_pay_token_for(order) }
      expect(response).to redirect_to(job_order_path(order.id))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
      expect(shopify.calls).to be_empty
    end

    it "redirects with the pay flash for a valid token of a soft-deleted order" do
      order = order_with_task!(owner: owner, status_key: :completed)
      minted = magic_pay_token_for(order)
      order.update!(is_deleted: true)
      get pay_job_orders_path, params: { token: minted }
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
    end

    # FIXED(D-J11): an unparsable, expired or pre-D-J11 token gets the "invalid or
    # has expired" redirect instead of the nil @job_order crash. (A valid token
    # on a non-COMPLETED order is covered below.)
    it "redirects with the expired flash for an invalid token" do
      order_with_task!(owner: owner, status_key: :completed)
      get pay_job_orders_path, params: { token: "bogus-token" }
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
      expect(shopify.calls).to be_empty
    end

    it "redirects with the expired flash for a legacy (pre-D-J11) token and for an approval token" do
      order = order_with_task!(owner: owner, status_key: :completed)
      [Rails.application.message_verifier(:job_order_id).generate(order.id), magic_link_token_for(order)].each do |bad|
        get pay_job_orders_path, params: { token: bad }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
      end
      expect(shopify.calls).to be_empty
    end

    # FIXED(D-J11): pay links expire after 14 days. Order and token are created
    # BEFORE the clock moves.
    it "works for 14 days and is refused afterwards" do
      order = order_with_task!(owner: owner, status_key: :completed)
      minted = magic_pay_token_for(order)
      travel_to(13.days.from_now) do
        get pay_job_orders_path, params: { token: minted }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("https://pay.example/inv")
      end
      travel_to(15.days.from_now) do
        get pay_job_orders_path, params: { token: minted }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.pay_magic_link_expired"))
      end
    end

    it "refuses a token issued for a different owner of the order" do
      order = order_with_task!(owner: owner, status_key: :completed)
      minted = magic_pay_token_for(order)
      order.update_columns(user_id: create(:user, :regular_user).id)
      get pay_job_orders_path, params: { token: minted }
      expect(response).to redirect_to(job_orders_path)
    end
  end
end
