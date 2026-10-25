# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for the job order workflow actions: quote, comments,
# processed, resend_quote_email and the magic-link approval pages.
# Mail is asserted by delivered outcome (recipient + subject).

RSpec.describe "JobOrders workflow", type: :request do
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

  def order_with_task!(status_key: :staff_approval, title: "Task #1")
    make_job_order!(owner: owner, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: title)
    end
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status&.name }
  end

  def error_text
    CGI.unescapeHTML(response.body)
  end

  def quote_params(task, extra = {})
    { approved: "true",
      "job_task_quote_price_#{task.id}" => "124.5",
      "task_#{task.id}_service_qty" => "2",
      "task_#{task.id}_service_price" => "3",
      job_order: { staff_comments: "use the big printer" } }.merge(extra)
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  # ------------------------------------------------------------- quote

  describe "PATCH quote" do
    let!(:order) { order_with_task! }
    let(:task) { order.job_tasks.first }

    it "lets the admin role quote an order (the recorded status user is the admin)" do
      session_login!(admin)
      patch job_order_quote_path(order), params: quote_params(task)
      expect(response).to redirect_to(job_order_path(order))
      expect(status_names(order)).to end_with("Waiting for User Approval")
      expect(order.job_order_statuses.last.user).to eq(admin)
      expect(deliveries.last.to).to eq([owner.email])
    end

    it "flashes the generic error for a non-blank junk approved value and changes nothing" do
      session_login!(staff)
      patch job_order_quote_path(order), params: quote_params(task, approved: "maybe")
      expect(response).to redirect_to(job_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      expect(task.reload.job_task_quote).to be_nil
      expect(deliveries).to be_empty
    end

    it "stores per-option prices for the task's selected options" do
      option = JobOption.create!(name: "Polish", fee: 1)
      task.job_task_options.create!(job_option: option)
      session_login!(staff)
      patch job_order_quote_path(order),
            params: quote_params(task, "task_#{task.id}_option_price_#{option.id}" => "7.25")

      quote_option = task.reload.job_task_quote.job_task_quote_options.first
      expect(quote_option.job_option).to eq(option)
      expect(quote_option.price).to eq(BigDecimal("7.25"))
    end

    it "skips options whose price is blank" do
      option = JobOption.create!(name: "Polish", fee: 1)
      task.job_task_options.create!(job_option: option)
      session_login!(staff)
      patch job_order_quote_path(order),
            params: quote_params(task, "task_#{task.id}_option_price_#{option.id}" => "")
      expect(task.reload.job_task_quote.job_task_quote_options).to be_empty
    end

    # WART(D-J42): missing price keys silently become 0.0
    it "writes 0.0 for price, service quantity and service price when the keys are missing" do
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", job_order: { staff_comments: "x" } }
      quote = task.reload.job_task_quote
      expect([quote.price, quote.service_quantity, quote.service_price]).to eq([0, 0, 0])
      expect(status_names(order)).to end_with("Waiting for User Approval")
    end

    # WART(D-J42): a negative price raises RecordInvalid; nothing is saved (rollback) and no mail goes out
    it "raises (422 RecordInvalid) for a negative price and rolls the whole quote back" do
      session_login!(staff)
      patch job_order_quote_path(order), params: quote_params(task, "job_task_quote_price_#{task.id}" => "-5")
      expect(response).to have_http_status(:unprocessable_content)
      expect(task.reload.job_task_quote).to be_nil
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
      expect(deliveries).to be_empty
    end

    # WART(D-J42): `params[:job_order][:staff_comments]` raises when the job_order key is absent,
    # inside the transaction, so the quote rows written before it are rolled back
    it "raises (500 NoMethodError) and rolls back when the job_order param is absent" do
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "10" }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
      expect(task.reload.job_task_quote).to be_nil
      expect(status_names(order)).to eq(["Waiting for Staff Approval"])
    end

    it "does not overwrite existing staff_comments with a blank value" do
      order.update!(staff_comments: "original note")
      session_login!(staff)
      patch job_order_quote_path(order), params: quote_params(task, job_order: { staff_comments: "" })
      expect(order.reload.staff_comments).to eq("original note")
    end

    it "keeps the existing line items when no job_quote_line_items param is sent" do
      order.job_quote_line_items.create!(description: "Existing", price: 3)
      session_login!(staff)
      patch job_order_quote_path(order), params: quote_params(task)
      expect(order.reload.job_quote_line_items.pluck(:description, :price)).to eq([["Existing", BigDecimal("3")]])
    end

    it "records the staff comment of a decline as a chat message and emails the customer" do
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "false", user_comments: "Sorry, we cannot make this" }
      expect(status_names(order)).to end_with("Declined")
      expect(order.chat_messages.last.message).to eq("Sorry, we cannot make this")
      expect(order.chat_messages.last.sender).to eq(staff)
      expect(deliveries.last.to).to eq([owner.email])
      expect(deliveries.last.subject).to eq("Your job ##{order.id} has been declined")
    end

    it "pins what happens to a disallowed staff file: the attach is ignored and the quote still completes" do
      session_login!(staff)
      patch job_order_quote_path(order),
            params: quote_params(task, "task_#{task.id}_staff_files" => [FilesTestHelper.mp4])
      expect(response).to redirect_to(job_order_path(order))
      expect(task.reload.staff_files.count).to eq(0)
      expect(status_names(order)).to end_with("Waiting for User Approval")
    end

    # WART(D-J33): no state guard: a PAID or Draft order is re-quoted, reset to
    # Waiting for User Approval and the customer is emailed.
    it "re-quotes a PAID order back to Waiting for User Approval and emails the customer" do
      paid = order_with_task!(status_key: :paid)
      session_login!(staff)
      patch job_order_quote_path(paid), params: quote_params(paid.job_tasks.first)

      expect(status_names(paid)).to eq(["Paid (Waiting for Pick-Up)", "Waiting for User Approval"])
      expect(deliveries.last.to).to eq([owner.email])
    end

    it "re-quotes a Draft order as well" do
      draft = order_with_task!(status_key: :draft)
      session_login!(staff)
      patch job_order_quote_path(draft), params: quote_params(draft.job_tasks.first)
      expect(status_names(draft)).to eq(["Draft", "Waiting for User Approval"])
    end

    # The round trip the customer takes: the quote mail carries a magic link,
    # which opens the approval page and approves with the owner's login.
    it "emails a magic link that opens the approval page and approves the quote" do
      session_login!(staff)
      patch job_order_quote_path(order), params: quote_params(task)
      body = deliveries.last.body.decoded
      token = CGI.unescape(body[/user_magic_approval\?token=([^"&\s]+)/, 1].to_s)
      expect(token).to be_present

      reset! # a different browser: a guest again
      get user_magic_approval_job_orders_path, params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approve the Quote")

      session_login!(owner)
      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }
      expect(response.body).to include("Thank You for Approving/Denying the Job Order!")
      expect(status_names(order)).to end_with("Waiting to be Processed")
    end
  end

  # ------------------------------------------------------------- comments

  describe "PATCH comments" do
    let!(:order) { order_with_task! }

    it "lets the admin role save staff comments" do
      session_login!(admin)
      patch job_order_comments_path(order), params: { job_order: { staff_comments: "admin note" } }
      expect(order.reload.staff_comments).to eq("admin note")
      expect(flash[:notice]).to eq(I18n.t("job_orders.alerts.updated_successfully"))
    end

    # WART(D-J39): `user_id` is permitted, so staff can reassign the order's owner
    it "lets staff reassign the order to another owner via a mass-assigned user_id" do
      session_login!(staff)
      patch job_order_comments_path(order), params: { job_order: { user_id: other.id } }
      expect(order.reload.user_id).to eq(other.id)
    end

    it "flashes the generic error when the update is invalid (disallowed staff upload)" do
      session_login!(staff)
      patch job_order_comments_path(order), params: { job_order: { staff_files: [FilesTestHelper.mp4] } }
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(order.reload.staff_files.count).to eq(0)
    end

    it "redirects to root with the parameter-missing message when job_order is absent" do
      session_login!(staff)
      patch job_order_comments_path(order)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("param is missing or the value is empty or invalid: job_order")
    end
  end

  # ------------------------------------------------------------- processed

  describe "PATCH processed" do
    let!(:order) { order_with_task!(status_key: :being_processed) }
    let(:task) { order.job_tasks.first }

    before { session_login!(staff) }

    it "does nothing and flashes the generic error when completed is false" do
      patch job_order_processed_path(order), params: { completed: "false" }
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(status_names(order)).to eq(["Currently being Processed"])
    end

    it "does nothing from a wrong status" do
      draft = order_with_task!(status_key: :draft)
      patch job_order_processed_path(draft), params: { completed: "true" }
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_while_updating"))
      expect(status_names(draft)).to eq(["Draft"])
    end

    it "lets the admin role complete an order" do
      task.build_job_task_quote(price: 10, service_price: 0, service_quantity: 0).save!
      session_login!(admin)
      patch job_order_processed_path(order), params: { completed: "true" }
      expect(status_names(order)).to end_with("Completed (Waiting for Payment)")
      expect(order.job_order_statuses.last.user).to eq(admin)
    end

    # WART(D-J15)
    it "answers format.js with the 500 (ActionView::Template::Error)" do
      patch job_order_processed_path(order), params: { completed: "true" },
                                             headers: { "ACCEPT" => "text/javascript" }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("ActionView::Template::Error")
    end

    # WART(D-J45): a zero-price order is auto-paid and ONLY the payment_succeeded
    # mail goes out; the staff-authored completion message is dropped.
    it "drops the completion message when a zero-price order is auto-paid" do
      task.build_job_task_quote(price: 0, service_price: 0, service_quantity: 0).save!
      patch job_order_processed_path(order),
            params: { completed: "true", send_email: "true", message: "<p>Custom note</p>" }

      expect(status_names(order)).to end_with("Paid (Waiting for Pick-Up)")
      expect(deliveries.map(&:subject)).to eq(["Your Job Order ##{order.id} is now ready for pickup"])
      expect(deliveries.last.body.encoded).not_to include("Custom note")
    end

    it "auto-pays an order with no quoted tasks at all (total 0)" do
      patch job_order_processed_path(order), params: { completed: "true" }
      expect(order.reload.total_price).to eq(0)
      expect(status_names(order)).to end_with("Paid (Waiting for Pick-Up)")
    end

    it "uses the default 'processed' message template when send_email is set with a blank message" do
      task.build_job_task_quote(price: 12.5, service_price: 0, service_quantity: 0).save!
      patch job_order_processed_path(order), params: { completed: "true", send_email: "true", message: "" }

      mail = deliveries.last
      expect(mail.subject).to eq("Your Job Order ##{order.id} has been completed")
      expect(mail.to).to eq([owner.email])
      expect(mail.bcc).to eq(["uottawa.makerepo@gmail.com"])
      expect(mail.body.encoded).to include("Your print has completed and is now available for pickup!")
      expect(mail.body.encoded).to include("Your order ID is #{order.id}")
    end

    it "sanitizes the custom completion message (script tags are stripped)" do
      task.build_job_task_quote(price: 12.5, service_price: 0, service_quantity: 0).save!
      patch job_order_processed_path(order),
            params: { completed: "true", send_email: "true",
                      message: "<p>Ready</p><script>alert(1)</script>" }

      body = deliveries.last.body.encoded
      expect(body).to include("Ready")
      expect(body).not_to include("<script>")
    end
  end

  # ------------------------------------------------------------- resend_quote_email

  describe "PATCH resend_quote_email" do
    # WART(D-J34): no state guard; a Draft order gets a quote link and the
    # reminder status makes that link usable for approval.
    it "works on a Draft order: records the reminder, mails a link and the link then opens the approval page" do
      draft = order_with_task!(status_key: :draft)
      session_login!(staff)
      patch job_order_resend_quote_email_path(draft)

      expect(status_names(draft)).to eq(["Draft", "Sent a Quote Reminder"])
      expect(deliveries.last.to).to eq([owner.email])

      token = magic_link_token_for(draft)
      reset!
      get user_magic_approval_job_orders_path, params: { token: token }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approve the Quote")
    end
  end

  # ------------------------------------------------------------- magic links

  describe "GET user_magic_approval" do
    let(:order) { order_with_task!(status_key: :user_approval) }
    let(:expired_flash) { I18n.t("job_orders.alerts.approval_magic_link_expired") }

    it "accepts the SENT_REMINDER state" do
      reminder = order_with_task!(status_key: :sent_reminder)
      get user_magic_approval_job_orders_path, params: { token: magic_link_token_for(reminder) }
      expect(response).to have_http_status(:ok)
    end

    %i[waiting_processed declined completed].each do |status_key|
      it "rejects an order in #{status_key}" do
        other_state = order_with_task!(status_key: status_key)
        get user_magic_approval_job_orders_path, params: { token: magic_link_token_for(other_state) }
        expect(response).to redirect_to(job_orders_path)
        expect(flash[:alert]).to eq(expired_flash)
      end
    end

    it "rejects a well-signed token for an order that does not exist" do
      token = Rails.application.message_verifier(:job_order_id).generate(99_999_999)
      get user_magic_approval_job_orders_path, params: { token: token }
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(expired_flash)
    end

    it "rejects a missing token and a token signed for another purpose" do
      get user_magic_approval_job_orders_path
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(expired_flash)

      foreign = Rails.application.message_verifier(:something_else).generate(order.id)
      get user_magic_approval_job_orders_path, params: { token: foreign }
      expect(response).to redirect_to(job_orders_path)
    end

    # WART(D-J09/D-J11): the page opens for any viewer holding the token, signed in or not
    it "renders for a signed-in user who is not the owner" do
      session_login!(other)
      get user_magic_approval_job_orders_path, params: { token: magic_link_token_for(order) }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Approve the Quote")
    end

    it "raises (500 NoMethodError) for an order without any status rows" do
      statusless = create(:job_order, user: owner)
      get user_magic_approval_job_orders_path, params: { token: magic_link_token_for(statusless) }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
    end
  end

  describe "PATCH user_magic_approval_confirmation" do
    let(:order) { order_with_task!(status_key: :user_approval) }
    let(:token) { magic_link_token_for(order) }

    it "approves from the SENT_REMINDER state for a signed-in user" do
      reminder = order_with_task!(status_key: :sent_reminder)
      session_login!(owner)
      patch user_magic_approval_confirmation_job_orders_path,
            params: { token: magic_link_token_for(reminder), approved: "true" }
      expect(status_names(reminder)).to end_with("Waiting to be Processed")
    end

    it "shows the error page and records nothing for a missing or garbage approved param" do
      session_login!(owner)
      ["maybe", nil].each do |value|
        patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: value }.compact
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("An error occured while trying to Approve/Deny the Job Order...")
      end
      expect(status_names(order)).to eq(["Waiting for User Approval"])
    end

    # WART(D-J10): a soft-deleted order is looked up as nil and dereferenced
    it "raises (500 NoMethodError) for a soft-deleted order" do
      order.update!(is_deleted: true)
      session_login!(owner)
      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }
      expect(response).to have_http_status(:internal_server_error)
      expect(error_text).to include("NoMethodError")
    end

    # WART(D-J11): any logged-in user holding the link can approve; the recorded actor is that user
    it "lets a signed-in non-owner approve and records them as the actor, without any staff mail" do
      session_login!(other)
      patch user_magic_approval_confirmation_job_orders_path, params: { token: token, approved: "true" }
      expect(status_names(order)).to end_with("Waiting to be Processed")
      expect(order.job_order_statuses.last.user).to eq(other)
      expect(deliveries).to be_empty
    end

    it "redirects with the accept/deny error flash when the token is missing" do
      patch user_magic_approval_confirmation_job_orders_path, params: { approved: "true" }
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.error_accept_deny_order"))
    end
  end
end
