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

  describe "D-J25: a guest chat message poisons the order" do
    let(:order) { order_with_task! }

    before do
      post chat_messages_path,
           params: { chat_message: { message: "hello from nowhere", job_order_id: order.id } }
      expect(response).to have_http_status(:no_content)
    end

    # WART(D-J25): the NULL-sender row is stored (D-J05), then the shared
    # partial `_message.html.erb` calls `chat_message.sender.name` on nil.
    it "stores a message without a sender" do
      message = ChatMessage.find_by!(message: "hello from nowhere")
      expect(message.sender_id).to be_nil
      expect(message.job_order_id).to eq(order.id)
    end

    it "makes the chat thread endpoint raise NoMethodError (500) for guests, owners and staff" do
      [nil, owner, staff].each do |viewer|
        session_login!(viewer) if viewer
        get chat_messages_path(job_order_id: order.id)
        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to include("NoMethodError")
        expect(error_text).to include("undefined method 'name' for nil")
      end
    end

    it "makes the order page itself 500 for the owner (the show page renders the same partial)" do
      session_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("undefined method 'name' for nil")
    end

    it "makes the order page 500 for staff too" do
      session_login!(staff)
      get job_order_path(order)
      expect(response).to have_http_status(:internal_server_error)
    end

    it "leaves other orders unaffected" do
      healthy = order_with_task!(title: "Task #1")
      session_login!(owner)
      get job_order_path(healthy)
      expect(response).to have_http_status(:ok)
    end

    it "also breaks the notification mail for that message" do
      message = ChatMessage.find_by!(message: "hello from nowhere")
      expect { ChatMessageMailer.new_message(message, [owner]).deliver_now }
        .to raise_error(NoMethodError, /email/)
    end

    # No notification is attempted for the guest message: `sender_id != NULL`
    # matches nobody, so no recipients are found and nothing is delivered.
    it "delivers no notification mail for the guest message (an owner message precedes it)" do
      ChatMessage.create!(job_order: order, sender: owner, message: "owner was here first")
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs do
        post chat_messages_path,
             params: { chat_message: { message: "second guest note", job_order_id: order.id } }
      end
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "cannot be saved again afterwards (the sender validation only passes on the unsaved User.new)" do
      message = ChatMessage.find_by!(message: "hello from nowhere")
      expect { message.save! }.to raise_error(ActiveRecord::RecordInvalid, /Sender must exist/)
    end
  end

  describe "D-J05: chat writes need no ownership" do
    # WART(D-J05): a signed-in stranger writes into the owner's order thread
    it "lets a signed-in non-participant post into someone else's order" do
      order = order_with_task!
      session_login!(other)

      expect do
        post chat_messages_path,
             params: { chat_message: { message: "stranger speaking", job_order_id: order.id } }
      end.to change { order.chat_messages.count }.by(1)

      expect(response).to have_http_status(:no_content)
      expect(order.chat_messages.last.sender).to eq(other)
    end

    it "accepts a message on a Draft order from a non-owner and a soft-deleted order" do
      draft = order_with_task!(status_key: :draft)
      deleted = order_with_task!
      deleted.update!(is_deleted: true)
      session_login!(other)

      [draft, deleted].each do |order|
        post chat_messages_path,
             params: { chat_message: { message: "anyone home?", job_order_id: order.id } }
        expect(response).to have_http_status(:no_content)
        expect(order.chat_messages.pluck(:message)).to eq(["anyone home?"])
      end
    end

    it "answers 204 with a failure flash for a missing or unknown job_order_id" do
      session_login!(other)
      post chat_messages_path, params: { chat_message: { message: "orphan" } }
      expect(response).to have_http_status(:no_content)
      expect(flash[:error]).to start_with("Failed to send message")
      expect(ChatMessage.where(message: "orphan")).to be_empty

      post chat_messages_path, params: { chat_message: { message: "orphan", job_order_id: 99_999_999 } }
      expect(response).to have_http_status(:no_content)
      expect(ChatMessage.where(message: "orphan")).to be_empty
    end
  end

  describe "D-J26: the wizard leaks uploads to guests" do
    let(:order) { order_with_task!(status_key: :draft) }
    let(:task) { order.job_tasks.first }

    before do
      task.update!(job_type: JobType.find_by!(name: "3D Print"))
      task.user_files.attach(FilesTestHelper.stl)
    end

    # WART(D-J26): edit has no gate (D-J03) and step 2 prints every uploaded
    # file's name, its attachment signed id (checkbox value) and a download link.
    it "shows a guest the filenames, signed ids and proxy download links of the owner's files" do
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(response).to have_http_status(:ok)
      attachment = task.reload.user_files.first
      expect(response.body).to include(attachment.filename.to_s)
      expect(response.body).to include(%(value="#{attachment.signed_id}"))
      expect(response.body).to include(%(name="job_task[user_files][]"))
      expect(response.body).to include("/rails/active_storage/blobs/proxy/#{attachment.blob.signed_id}/")
    end

    it "lets the guest actually download the file through the leaked link (UNVERIFIED in the review: confirmed)" do
      get edit_job_order_job_task_path(order, task, step: 2)
      link = response.body[%r{/rails/active_storage/blobs/proxy/[^"?]+}]
      expect(link).to be_present

      get link
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to eq(File.size(Rails.root.join("spec/support/assets/test.stl")))
    end

    it "leaks to a signed-in stranger the same way" do
      session_login!(other)
      get edit_job_order_job_task_path(order, task, step: 2)
      expect(response.body).to include(task.user_files.first.filename.to_s)
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

    # WART(D-J02/D-J35): delete has no gate and no state guard; the has_one
    # :job_task_quote (and its options) are destroyed with the task.
    it "lets a guest delete a task of a COMPLETED, quoted order and the total drops" do
      expect(order.reload.total_price).to eq(55)
      quote_id = task.job_task_quote.id

      expect do
        delete job_order_job_task_path(order, task)
      end.to change(JobTask, :count).by(-1)
        .and change(JobTaskQuote, :count).by(-1)
        .and change(JobTaskQuoteOption, :count).by(-1)

      expect(response).to redirect_to(job_order_path(order))
      expect(JobTaskQuote.exists?(quote_id)).to be(false)
      expect(order.reload.total_price).to eq(5) # only the line item is left
      expect(order.job_order_statuses.last.job_status).to eq(JobStatus::COMPLETED)
    end

    it "also works on a PAID order and on a soft-deleted order" do
      advance = order.job_order_statuses.create!(job_status: JobStatus::PAID, user: owner)
      expect(advance).to be_persisted
      order.update!(is_deleted: true) # D-J48: task routes use a plain JobOrder.find

      delete job_order_job_task_path(order, task)
      expect(response).to redirect_to(job_order_path(order))
      expect(JobTask.exists?(task.id)).to be(false)
    end

  end

  describe "D-J35: the owner can still edit after submission" do
    # WART(D-J35): allow_edit? is only consulted by views; update has no state guard
    it "lets the owner change the job type of a task on a PAID order" do
      order = order_with_task!(status_key: :paid)
      task = order.job_tasks.first
      session_login!(owner)

      patch job_order_job_task_path(order, task),
            params: { step: "1", job_task: { job_type_id: JobType.find_by!(name: "Laser Cut").id } }

      expect(task.reload.job_type.name).to eq("Laser Cut")
      expect(order.reload.job_order_statuses.last.job_status).to eq(JobStatus::PAID)
    end

    it "lets the owner create a new task on a PICKED_UP order" do
      order = order_with_task!(status_key: :picked_up)
      session_login!(owner)
      expect { post job_order_job_tasks_path(order) }.to change { order.job_tasks.count }.by(1)
    end
  end
end
