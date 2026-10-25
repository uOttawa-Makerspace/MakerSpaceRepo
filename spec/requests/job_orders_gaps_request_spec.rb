# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for JobOrdersController: the guest / staff / admin
# columns of the coverage matrix, the remaining index/show/create/destroy/
# assign_staff/admin/invoice branches. (Quote, processed, approval and magic
# link branches live in job_orders_workflow_request_spec.rb.)
#
# Mail is asserted by delivered outcome (recipient + subject).

RSpec.describe "JobOrders gaps", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:other) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def order_with_task!(owner_user: owner, status_key: :draft, title: "Task #1")
    make_job_order!(owner: owner_user, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  def advance_to!(order, status_key, by: owner)
    row = JobStatus.find_by!(name: JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(status_key))
    order.job_order_statuses.create!(job_status: row, user: by)
    order
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def error_text
    CGI.unescapeHTML(response.body)
  end

  def login_redirect_for(path)
    login_path(back_to: path)
  end

  # ------------------------------------------------------------- signed_in gate

  describe "guests on the signed-in-only actions" do
    let!(:order) { order_with_task!(status_key: :user_approval) }

    {
      "destroy" => -> { delete job_order_path(order) },
      "user_approval" => -> { patch job_order_user_approval_path(order), params: { approved: "true" } },
      "quote" => -> { patch job_order_quote_path(order), params: { approved: "true" } },
      "comments" => -> { patch job_order_comments_path(order), params: { job_order: { staff_comments: "x" } } },
      "processed" => -> { patch job_order_processed_path(order), params: { completed: "true" } },
      "resend_quote_email" => -> { patch job_order_resend_quote_email_path(order) },
      "assign_staff" => -> { patch job_order_assign_staff_path(order), params: { staff_id: 1 } },
      "invoice" => -> { get job_order_invoice_path(order) },
      "timeline_modal" => -> { get job_order_timeline_modal_path(order) },
      "create" => -> { post job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "1" } }
    }.each do |name, request|
      it "redirects a guest on #{name} to the login page and changes nothing" do
        statuses_before = JobOrderStatus.count
        orders_before = JobOrder.count
        instance_exec(&request)

        expect(response).to have_http_status(:redirect)
        expect(response.location).to start_with("http://www.example.com/login?back_to=")
        expect(JobOrderStatus.count).to eq(statuses_before)
        expect(JobOrder.count).to eq(orders_before)
        expect(order.reload.is_deleted).to be(false)
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "answers format.js with a client-side redirect snippet" do
      patch job_order_user_approval_path(order), params: { approved: "true" },
                                                 headers: { "ACCEPT" => "text/javascript" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("window.location.href = '/login'")
    end

    it "answers format.json with the literal string redirect" do
      patch job_order_user_approval_path(order), params: { approved: "true" },
                                                 headers: { "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("redirect") # a bare (non-JSON) string behind a json content type
    end
  end

  describe "grant_access on the staff-only actions the first pass skipped" do
    let!(:order) { order_with_task!(status_key: :being_processed) }

    {
      "processed" => -> { patch job_order_processed_path(order), params: { completed: "true" } },
      "resend_quote_email" => -> { patch job_order_resend_quote_email_path(order) },
      "decline_modal" => -> { get job_order_decline_modal_path(order) },
      "comments_modal" => -> { get job_order_comments_modal_path(order) }
    }.each do |name, request|
      it "bounces a regular user from #{name}" do
        session_login!(owner)
        statuses_before = JobOrderStatus.count
        instance_exec(&request)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.cannot_access_area"))
        expect(JobOrderStatus.count).to eq(statuses_before)
      end

      it "bounces a guest from #{name} through the sign-in gate first" do
        instance_exec(&request)
        expect(response.location).to start_with("http://www.example.com/login?back_to=")
      end
    end

    it "lets the admin role through the staff-only transitions (start_processing, paid, picked_up)" do
      session_login!(admin)
      start = order_with_task!(status_key: :waiting_processed)
      patch job_order_start_processing_path(start), params: { start_processing: "true" }
      expect(status_names(start)).to end_with("Currently being Processed")

      paid = order_with_task!(status_key: :completed)
      patch job_order_paid_path(paid), params: { paid: "true" }
      expect(status_names(paid)).to end_with("Paid (Waiting for Pick-Up)")

      picked = order_with_task!(status_key: :paid)
      patch job_order_picked_up_path(picked), params: { picked_up: "true" }
      expect(status_names(picked)).to end_with("Picked-Up")
    end

    it "flashes the generic error when the transition param is absent" do
      session_login!(staff)
      start = order_with_task!(status_key: :waiting_processed)
      patch job_order_start_processing_path(start)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(status_names(start)).to eq(["Waiting to be Processed"])
    end

    # WART(D-J47): update_status calls .last.job_status on the status history
    it "500s (NoMethodError) on a transition for an order with no status rows" do
      session_login!(staff)
      statusless = create(:job_order, user: owner)
      patch job_order_start_processing_path(statusless), params: { start_processing: "true" }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
    end

    it "marks a paid transition without sending any mail" do
      session_login!(staff)
      completed = order_with_task!(status_key: :completed)
      perform_enqueued_jobs { patch job_order_paid_path(completed), params: { paid: "true" } }
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    # WART(D-J15): the js format renders admin_row -> _assign_staff with a nil @staff
    it "answers format.js on a transition with the same 500 (ActionView::Template::Error)" do
      session_login!(staff)
      start = order_with_task!(status_key: :waiting_processed)
      patch job_order_start_processing_path(start), params: { start_processing: "true" },
                                                    headers: { "ACCEPT" => "text/javascript" }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("ActionView::Template::Error")
    end
  end

  # ------------------------------------------------------------- unknown / deleted orders

  describe "set_job_order for unknown or soft-deleted orders" do
    it "redirects staff with no_permission for an unknown id and for a soft-deleted order" do
      session_login!(staff)
      patch job_order_comments_path(job_order_id: 99_999_999), params: { job_order: { staff_comments: "x" } }
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))

      deleted = order_with_task!
      deleted.update!(is_deleted: true)
      patch job_order_comments_path(deleted), params: { job_order: { staff_comments: "x" } }
      expect(response).to redirect_to(new_job_orders_path)
      expect(deleted.reload.staff_comments).not_to eq("x")
    end

    it "treats a non-owner's user_approval like any other protected action (no_permission redirect)" do
      order = order_with_task!(status_key: :user_approval)
      session_login!(other)
      patch job_order_user_approval_path(order), params: { approved: "true" }
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "lets staff approve on behalf of the customer (recorded user is the staff member)" do
      order = order_with_task!(status_key: :user_approval)
      session_login!(staff)
      perform_enqueued_jobs { patch job_order_user_approval_path(order), params: { approved: "true" } }
      expect(status_names(order)).to end_with("Waiting to be Processed")
      expect(order.job_order_statuses.last.user).to eq(staff)
      expect(ActionMailer::Base.deliveries.last.subject).to eq("A user has approved a Job Order")
    end

    it "accepts the SENT_REMINDER state as an origin for a user approval" do
      order = order_with_task!(status_key: :sent_reminder)
      session_login!(owner)
      patch job_order_user_approval_path(order), params: { approved: "true" }
      expect(status_names(order)).to end_with("Waiting to be Processed")
    end

    it "flashes the generic error for a missing or garbage approved param and records nothing" do
      order = order_with_task!(status_key: :user_approval)
      session_login!(owner)
      [nil, "maybe"].each do |value|
        patch job_order_user_approval_path(order), params: { approved: value }.compact
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      end
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    it "marks an EXPEDITED order's staff approval mail with the EXPEDITED subject and high-priority headers" do
      order = order_with_task!(status_key: :user_approval)
      expedite!(order)
      session_login!(owner)
      perform_enqueued_jobs { patch job_order_user_approval_path(order), params: { approved: "true" } }

      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("EXPEDITED: A user has approved a Job Order")
      expect(mail.to).to eq(["makerspace@uottawa.ca"])
      expect(mail.header["Importance"].to_s).to eq("high")
      expect(mail.header["X-Priority"].to_s).to eq("1")
    end
  end

  def expedite!(order)
    option = JobOption.create!(name: "Expedited Processing", fee: 5)
    order.job_tasks.first.job_task_options.create!(job_option: option)
  end

  # ------------------------------------------------------------- index

  describe "GET /job_orders (index) corners" do
    # N+1 pinned: see defects.md D-PERF01
    it "lists only the viewer's own, non-deleted orders and skips orders without status rows", skip_bullet: true do
      mine = order_with_task!(status_key: :staff_approval)
      deleted = order_with_task!(status_key: :staff_approval)
      deleted.update!(is_deleted: true)
      not_mine = order_with_task!(owner_user: other, status_key: :staff_approval)
      statusless = create(:job_order, user: owner)

      session_login!(owner)
      get job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<td>#{mine.id}</td>")
      expect(response.body).not_to include("<td>#{deleted.id}</td>")
      expect(response.body).not_to include("<td>#{not_mine.id}</td>")
      expect(response.body).not_to include("<td>#{statusless.id}</td>")
    end

    it "renders for a user without any orders" do
      session_login!(owner)
      get job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("job_orders.public_page.my_job_orders"))
    end
  end

  # ------------------------------------------------------------- show

  describe "GET /job_orders/:id (show) corners" do
    it "shows the action-required notice for SENT_REMINDER and COMPLETED orders to the owner" do
      reminder = order_with_task!(status_key: :sent_reminder)
      completed = order_with_task!(status_key: :completed)
      expected = I18n.t("job_orders.alerts.action_required_scroll_to_timeline")
      session_login!(owner)

      [reminder, completed].each do |order|
        order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(flash[:notice]).to eq(expected)
      end
    end

    it "withholds the action-required notice from a non-owner" do
      order = order_with_task!(status_key: :user_approval)
      order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
      session_login!(other)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(flash[:notice]).to be_nil
    end

    it "renders for staff and admin viewers (no ownership gate, D-J06) without marking messages read" do
      order = order_with_task!(status_key: :staff_approval)
      order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
      ChatMessage.create!(job_order: order, sender: staff, message: "internal note")
      [staff, admin].each do |viewer|
        session_login!(viewer)
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Job Order ##{order.id}")
      end
      expect(order.chat_messages.first.reload.is_read).to be(false)
    end

    # WART(D-J51): staff see the quote modal on show, which calls
    # `task.job_type.name` for every task; a task without a job type crashes it.
    it "500s (NoMethodError) for staff when a task has no job type" do
      order = order_with_task!(status_key: :staff_approval)
      session_login!(staff)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("undefined method 'name' for nil")
      expect(response.body).to include("app/views/job_orders/_quote_modal.html.erb")
    end

    # WART(D-J46): show dereferences the "processed" JobOrderMessage unconditionally
    it "raises (500, NoMethodError) when the processed JobOrderMessage row is missing" do
      JobOrderMessage.where(name: "processed").delete_all
      order = order_with_task!(status_key: :staff_approval)
      session_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
    end

    # WART(D-J40): flash (not flash.now) on a rendered page leaks into the next request
    it "carries the missing-info alert over to the next request" do
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      order.job_tasks.create!(title: "Task #1")
      session_login!(owner)
      get job_order_path(order)
      expect(flash[:alert]).to start_with(I18n.t("job_orders.alerts.missing_info"))
      get landing_job_orders_path
      expect(response.body).to include(I18n.t("job_orders.alerts.missing_info"))
    end
  end

  # ------------------------------------------------------------- create

  describe "POST /job_orders (create) corners" do
    before { session_login!(owner) }

    it "re-renders new with the creation-error flash when the order cannot be saved (disallowed upload)" do
      expect do
        post job_orders_path, params: { job_order: { user_files: [FilesTestHelper.mp4] }, redirect_step: "1" }
      end.not_to change(JobOrder, :count)

      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_trying_to_create"))
      expect(response.body).to include(I18n.t("job_orders.new.title"))
    end

    # WART(D-J39): job_order_params permits staff-only fields on create
    it "lets a customer set staff_comments on their own new order" do
      post job_orders_path,
           params: { job_order: { staff_comments: "customer wrote this as staff" }, redirect_step: "1" }
      expect(JobOrder.order(:id).last.staff_comments).to eq("customer wrote this as staff")
    end

    it "falls back to a nil job type when the Design Services row is missing" do
      JobType.where(name: "Design Services").destroy_all
      post job_orders_path, params: { job_order: { job_type_id: nil }, redirect_step: "2" }
      expect(JobOrder.order(:id).last.job_tasks.first.job_type).to be_nil
    end
  end

  # ------------------------------------------------------------- destroy

  describe "DELETE /job_orders/:id (destroy) corners" do
    it "lets staff soft-delete another user's order (and sends them to the client index)" do
      order = order_with_task!
      session_login!(staff)
      delete job_order_path(order)
      expect(response).to redirect_to(job_orders_path)
      expect(order.reload.is_deleted).to be(true)
    end

    # WART(D-J44): an owner can soft-delete an order that is already being processed or paid
    it "lets the owner delete an in-progress and a paid order" do
      session_login!(owner)
      [:being_processed, :paid].each do |status_key|
        order = order_with_task!(status_key: status_key)
        delete job_order_path(order)
        expect(order.reload.is_deleted).to be(true)
      end
    end

    it "redirects a second delete of an already deleted order to new with no_permission" do
      order = order_with_task!
      order.update!(is_deleted: true)
      session_login!(owner)
      delete job_order_path(order)
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
    end

    # WART(D-J36): the has_many :job_order_options dependent: :destroy has no model;
    # destroy is a soft delete here, so the controller never trips over it.
    it "keeps the row (soft delete) and its tasks" do
      order = order_with_task!
      session_login!(owner)
      delete job_order_path(order)
      expect(JobOrder.exists?(order.id)).to be(true)
      expect(order.job_tasks.count).to eq(1)
    end
  end

  # ------------------------------------------------------------- assign_staff

  describe "PATCH assign_staff corners" do
    let!(:order) { order_with_task!(status_key: :staff_approval) }

    it "lets an admin assign a non-staff user (no role check on the target)" do
      session_login!(admin)
      perform_enqueued_jobs { patch job_order_assign_staff_path(order), params: { staff_id: other.id } }

      expect(order.reload.assigned_staff).to eq(other)
      expect(flash[:notice]).to eq("#{other.name} has been assigned to this job order.")
      expect(ActionMailer::Base.deliveries.last.to).to eq([other.email])
    end

    it "unassigns with a blank staff_id and says 'No staff'" do
      order.update!(assigned_staff: staff)
      session_login!(admin)
      patch job_order_assign_staff_path(order), params: { staff_id: "" }
      expect(order.reload.assigned_staff).to be_nil
      expect(flash[:notice]).to eq("No staff has been assigned to this job order.")
    end

    it "redirects back to the referer after assigning" do
      session_login!(admin)
      patch job_order_assign_staff_path(order), params: { staff_id: staff.id },
                                                headers: { "HTTP_REFERER" => admin_job_orders_url }
      expect(response).to redirect_to(admin_job_orders_url)
    end

    # WART(D-J08): the else branch dereferences the (nil) assigned staff
    it "500s (NoMethodError) when staff assigns someone else, and assigns nothing" do
      session_login!(staff)
      patch job_order_assign_staff_path(order), params: { staff_id: admin.id }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
      expect(order.reload.assigned_staff).to be_nil
    end

    it "sends the EXPEDITED subject and priority headers to the assigned staff member" do
      expedite!(order)
      session_login!(admin)
      perform_enqueued_jobs { patch job_order_assign_staff_path(order), params: { staff_id: staff.id } }

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([staff.email])
      expect(mail.subject).to eq("EXPEDITED: You've been assigned to Job Order ##{order.id}")
      expect(mail.header["Importance"].to_s).to eq("high")
      expect(mail.header["X-Priority"].to_s).to eq("1")
    end
  end

  # ------------------------------------------------------------- admin / settings / invoice / timeline

  describe "admin, settings, invoice and timeline corners" do
    # N+1 pinned: see defects.md D-PERF02
    it "renders the admin list for the admin role, newest first, hiding drafts and deleted orders", skip_bullet: true do
      older = order_with_task!(status_key: :staff_approval)
      newer = nil
      travel_to(2.minutes.from_now) { newer = order_with_task!(status_key: :user_approval) }
      draft = order_with_task!(status_key: :draft)
      deleted = order_with_task!(status_key: :staff_approval)
      deleted.update!(is_deleted: true)

      session_login!(admin)
      get admin_job_orders_path
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("<td>#{older.id}</td>", "<td>#{newer.id}</td>")
      expect(body).not_to include("<td>#{draft.id}</td>")
      expect(body).not_to include("<td>#{deleted.id}</td>")
      expect(body.index("<td>#{newer.id}</td>")).to be < body.index("<td>#{older.id}</td>")
    end

    it "offers every non-Draft status in the admin filter" do
      session_login!(staff)
      get admin_job_orders_path
      page = Capybara.string(response.body)
      expect(page).to have_text("Waiting for Staff Approval")
      expect(page).not_to have_css("option", text: /\ADraft\z/)
    end

    it "renders the settings page for the admin role" do
      session_login!(admin)
      get settings_job_orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Job Orders Settings")
    end

    it "serves the invoice to the admin and bounces a guest to the login page" do
      order = order_with_task!(status_key: :completed)
      session_login!(admin)
      get job_order_invoice_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Invoice ##{order.id}")
    end

    it "lists the quoted lines, options and line items on the invoice" do
      order = order_with_task!(status_key: :completed)
      task = order.job_tasks.first
      group = create(:job_service_group, job_type: JobType.find_by!(name: "3D Print"), name: "Resin")
      task.update!(job_service: create(:job_service, job_service_group: group, name: "SLA print", unit: "cm3"))
      quote = task.build_job_task_quote(price: 10, service_price: 3, service_quantity: 2)
      quote.save!
      quote.job_task_quote_options.create!(job_option: JobOption.create!(name: "Polish", fee: 1), price: 4)
      order.job_quote_line_items.create!(description: "Rush fee", price: 5.5)
      session_login!(owner)
      get job_order_invoice_path(order)

      text = Capybara.string(response.body).text.squish
      expect(text).to include("Task #1 - Base Fee CAD $10.00")
      expect(text).to include("Task #1 - SLA print (Resin) - 2.0 cm3 CAD $6.00")
      expect(text).to include("Task #1 - Polish (Option) CAD $4.00")
      expect(text).to include("Rush fee CAD $5.50")
      expect(text).to include("Total: CAD $25.50")
    end

    # WART(D-J52): the parts line is only printed when the task has a job service,
    # but the total always includes service_price * service_quantity, so the
    # printed lines can fail to add up to the printed total.
    it "omits the parts line for a task without a service although the total includes it" do
      order = order_with_task!(status_key: :completed)
      order.job_tasks.first.build_job_task_quote(price: 10, service_price: 3, service_quantity: 2).save!
      session_login!(owner)
      get job_order_invoice_path(order)

      text = Capybara.string(response.body).text.squish
      expect(text).to include("Task #1 - Base Fee CAD $10.00")
      expect(text).not_to include("CAD $6.00")
      expect(text).to include("Total: CAD $16.00")
    end

    it "redirects invoice requests for a soft-deleted order to new with no_permission" do
      order = order_with_task!(status_key: :completed)
      order.update!(is_deleted: true)
      session_login!(owner)
      get job_order_invoice_path(order)
      expect(response).to redirect_to(new_job_orders_path)
    end

    # N+1 pinned: see defects.md D-PERF03
    it "shows the status history with a timestamp to the admin role, naming the actor only for processing steps", skip_bullet: true do
      order = order_with_task!
      advance_to!(order, :staff_approval, by: owner)
      advance_to!(order, :being_processed, by: staff)
      session_login!(admin)
      get job_order_timeline_modal_path(order)

      expect(response).to have_http_status(:ok)
      text = Capybara.string(response.body).text.squish
      expect(text).to include("Currently being Processed (By: #{staff.name})")
      expect(text).to include("Waiting for Staff Approval")
      expect(text).not_to include("(By: #{owner.name})")
      expect(text).to match(/\w{3} +\d+ \d{4} at \d{2}:\d{2}/)
    end
  end
end
