# frozen_string_literal: true

require "rails_helper"

# Chunk 11: the severity-1 job-order defects whose DAMAGE (not just the missing
# gate) was unpinned in chunk 6.
#
#   D-J25  a guest chat POST stores a NULL-sender row that then bricks the chat
#          thread AND the order page for everybody
#   D-J26  the wizard step-2 page leaks upload filenames, signed ids and download
#          links to guests
#   D-J02 / D-J35  a guest task delete cascades to the quote and changes the
#          order total
#   D-J05  any signed-in user can post into someone else's order
#
# These pin CURRENT behavior; Stage 2b flips them.

RSpec.describe "Job order security pins", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:other) { create(:user, :regular_user) }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  # the debug error page HTML-escapes quotes in the exception message
  def error_text
    CGI.unescapeHTML(response.body)
  end

  def order_with_task!(status_key: :staff_approval, title: "Task #1")
    make_job_order!(owner: owner, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  describe "D-J25: a NULL-sender chat row can no longer poison the order" do
    let(:order) { order_with_task! }

    # A legacy row, as it could exist before the fix / data migration.
    let!(:legacy) do
      ChatMessage.new(job_order: order, sender_id: nil, message: "hello from nowhere").tap { |m| m.save!(validate: false) }
    end

    # FIXED(D-J25): the partial is nil-safe ("Unknown"), so a stray row never 500s
    it "renders the chat thread with an Unknown sender for owners and staff" do
      [owner, staff].each do |viewer|
        session_login!(viewer)
        get chat_messages_path(job_order_id: order.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("hello from nowhere")
        expect(response.body).to include("Unknown")
      end
    end

    it "renders the order page for the owner and for staff" do
      # (a task without a job type breaks the staff quote modal: separate, unfixed defect)
      order.job_tasks.first.update!(job_type: JobType.find_by!(name: "3D Print"))
      [owner, staff].each do |viewer|
        session_login!(viewer)
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Unknown")
      end
    end

    it "a guest POST stores nothing and does not break the order page" do
      expect do
        post chat_messages_path,
             params: { chat_message: { message: "guest note", job_order_id: order.id } }
      end.not_to(change { ChatMessage.count })

      session_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
    end

    it "the model rejects a message without a sender (also for the unsaved guest User.new)" do
      expect(ChatMessage.new(job_order: order, sender: User.new, message: "x")).not_to be_valid
      expect(ChatMessage.new(job_order: order, message: "x")).not_to be_valid
    end

    it "cannot be saved again while the sender is missing" do
      expect { legacy.save! }.to raise_error(ActiveRecord::RecordInvalid, /Sender/)
    end
  end

  describe "D-J05: chat writes need order access" do
    # FIXED(D-J05): signed-in strangers are forbidden; owner/staff/admin may post
    it "forbids a signed-in non-participant" do
      order = order_with_task!
      session_login!(other)

      expect do
        post chat_messages_path,
             params: { chat_message: { message: "stranger speaking", job_order_id: order.id } }
      end.not_to(change { order.chat_messages.count })

      expect(response).to have_http_status(:forbidden)
    end

    it "lets the owner post on a Draft order but refuses a soft-deleted order" do
      draft = order_with_task!(status_key: :draft)
      deleted = order_with_task!
      deleted.update!(is_deleted: true)
      session_login!(owner)

      post chat_messages_path, params: { chat_message: { message: "anyone home?", job_order_id: draft.id } }
      expect(response).to have_http_status(:no_content)
      expect(draft.chat_messages.pluck(:message)).to eq(["anyone home?"])

      # FIXED(retro of A2): a deleted order answers 404, with no sticky flash
      post chat_messages_path, params: { chat_message: { message: "anyone home?", job_order_id: deleted.id } }
      expect(response).to have_http_status(:not_found)
      expect(flash[:error]).to be_nil
      expect(deleted.chat_messages).to be_empty
    end

    # FIXED(retro of A2): 404 instead of 204 plus a sticky flash
    it "answers 404 without a flash for a missing or unknown job_order_id" do
      session_login!(other)
      post chat_messages_path, params: { chat_message: { message: "orphan" } }
      expect(response).to have_http_status(:not_found)
      expect(flash[:error]).to be_nil
      expect(ChatMessage.where(message: "orphan")).to be_empty

      post chat_messages_path, params: { chat_message: { message: "orphan", job_order_id: 99_999_999 } }
      expect(response).to have_http_status(:not_found)
      expect(ChatMessage.where(message: "orphan")).to be_empty
    end
  end

  describe "D-J26: the wizard no longer leaks uploads" do
    let(:order) { order_with_task!(status_key: :draft) }
    let(:task) { order.job_tasks.first }

    before do
      task.update!(job_type: JobType.find_by!(name: "3D Print"))
      task.user_files.attach(FilesTestHelper.stl)
    end

    # FIXED(D-J26): the edit gate (D-J03) blocks guests/strangers, and only the
    # owner/admin (who can submit the form) get the signed-id checkbox.
    it "shows a guest nothing (redirect to login)" do
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include(task.user_files.first.filename.to_s)
      expect(response.body).not_to include("/rails/active_storage/blobs/")
    end

    it "shows a signed-in stranger nothing" do
      session_login!(other)
      get edit_job_order_job_task_path(order, task, step: 2)
      expect(response).to redirect_to(new_job_orders_path)
      expect(response.body).not_to include(task.user_files.first.filename.to_s)
    end

    it "gives the owner the filenames, signed-id checkbox and download link" do
      session_login!(owner)
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(response).to have_http_status(:ok)
      attachment = task.reload.user_files.first
      expect(response.body).to include(attachment.filename.to_s)
      expect(response.body).to include(%(value="#{attachment.signed_id}"))
      expect(response.body).to include(%(name="job_task[user_files][]"))
      expect(response.body).to include("/rails/active_storage/blobs/proxy/#{attachment.blob.signed_id}/")
    end

    it "shows staff the filename and download link but no signed-id checkbox" do
      session_login!(staff)
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(response).to have_http_status(:ok)
      attachment = task.reload.user_files.first
      expect(response.body).to include(attachment.filename.to_s)
      expect(response.body).not_to include(%(value="#{attachment.signed_id}"))
      expect(response.body).to include("/rails/active_storage/blobs/proxy/")
    end
  end

  describe "D-J02 / D-J35: a task delete cascades to the money" do
    let(:order) { order_with_task!(status_key: :completed) }
    let(:task) { order.job_tasks.first }

    before do
      quote = task.build_job_task_quote(price: 40, service_price: 3, service_quantity: 2)
      quote.save!
      quote.job_task_quote_options.create!(job_option: JobOption.create!(name: "Polish", fee: 1), price: 4)
      order.job_quote_line_items.create!(description: "Rush", price: 5)
    end

    # FIXED(D-J02): guests and strangers can no longer delete (and so cascade the
    # quote). The OWNER may still delete after the quote (owner decision), which
    # now sends the order back to staff (JOB-01); after payment it is refused.
    it "refuses a guest and a stranger on a COMPLETED, quoted order" do
      expect(order.reload.total_price).to eq(55)

      expect { delete job_order_job_task_path(order, task) }.not_to change(JobTask, :count)
      session_login!(other)
      expect do
        delete job_order_job_task_path(order, task)
      end.not_to change(JobTaskQuote, :count)

      expect(order.reload.total_price).to eq(55)
    end

    it "lets the owner delete from a COMPLETED order, cascading the quote and sending it back to staff (JOB-01)" do
      session_login!(owner)
      expect do
        delete job_order_job_task_path(order, task)
      end.to change(JobTask, :count).by(-1)
        .and change(JobTaskQuote, :count).by(-1)
        .and change(JobTaskQuoteOption, :count).by(-1)

      expect(response).to redirect_to(job_order_path(order))
      expect(order.reload.total_price).to eq(5)
      expect(order.job_order_statuses.last.job_status).to eq(JobStatus::STAFF_APPROVAL)
    end

    it "404s on a soft-deleted order (D-J48)" do
      order.update!(is_deleted: true)
      session_login!(owner)
      delete job_order_job_task_path(order, task)
      expect(response).to have_http_status(:not_found)
      expect(JobTask.exists?(task.id)).to be(true)
    end
  end

  # FIXED(D-J35 / JOB-01): once paid, the wizard refuses every change (the
  # status is checked by JobOrder#apply_owner_change! under the row lock).
  # Changes to a quoted order are covered in job_orders_owner_change_request_spec.
  describe "D-J35: no owner change after payment" do
    it "refuses to change the job type of a task on a PAID order" do
      order = order_with_task!(status_key: :paid)
      task = order.job_tasks.first
      session_login!(owner)

      patch job_order_job_task_path(order, task),
            params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "Laser Cut").id } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.paid_order_cannot_change"))
      expect(task.reload.job_type).to be_nil
      expect(order.reload.job_order_statuses.last.job_status).to eq(JobStatus::PAID)
    end

    it "refuses to create a new task on a PICKED_UP order" do
      order = order_with_task!(status_key: :picked_up)
      session_login!(owner)
      expect { post job_order_job_tasks_path(order) }.not_to(change { order.job_tasks.count })
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.paid_order_cannot_change"))
    end
  end
end
