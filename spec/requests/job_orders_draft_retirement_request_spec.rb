# frozen_string_literal: true

require "rails_helper"

# JOB-03 review 3: a live Shopify draft is a payable invoice, and the customer
# may already hold its URL. Every status change goes through
# JobOrder#transition! / #enter_status!, whose destination rule decides what
# happens to the draft, inside the same locked transaction:
#   COMPLETED            kept (/pay serves it while current)
#   PAID, PICKED_UP      kept only if Shopify reports it COMPLETED (paid through
#                        it); an open draft (paid in store) is deleted; leaving PAID asks Shopify nothing
#   everything else      deleted
# A delete Shopify refuses refuses the status change; nothing is committed.
RSpec.describe "Job order drafts on status changes", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/invoice" } }
  let(:draft_id) { "gid://shopify/DraftOrder/9001" }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def shopify_ops
    shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
  end

  def status_names(order)
    order.reload.job_order_statuses.order(:id).map { |s| s.job_status.name }
  end

  # an order in `status_key` holding a current draft (as /pay created it)
  def order_with_draft!(status_key, price: 29.99)
    order = make_job_order!(owner: owner, status_key: status_key)
    task = order.job_tasks.create!(title: "Task #1")
    task.build_job_task_quote(price: price, service_price: 0, service_quantity: 0).save!
    order.update_columns(shopify_draft_order_id: draft_id,
                         shopify_draft_order_fingerprint: JobOrder.find(order.id).quote_fingerprint)
    [order.reload, task]
  end

  def refuse_delete!
    shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete a completed draft order" }]
  end

  describe "declining" do
    it "voids the draft when the customer declines through the emailed link" do
      order, = order_with_draft!(:user_approval)
      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "false" }

      expect(status_names(order).last).to eq("Declined")
      expect(shopify_ops).to eq(%w[draftOrderDelete])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "voids the draft when staff decline a COMPLETED order" do
      order, = order_with_draft!(:completed)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "false", job_order: { staff_comments: "" } }

      expect(status_names(order).last).to eq("Declined")
      expect(shopify_ops).to eq(%w[draftOrderDelete])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "refuses the decline and changes nothing when Shopify will not delete the draft" do
      order, = order_with_draft!(:completed)
      refuse_delete!
      before = status_names(order)
      session_login!(staff)
      patch job_order_quote_path(order),
            params: { approved: "false", user_comments: "no", job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.draft_not_voidable"))
      expect(status_names(order)).to eq(before)
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
      expect(order.chat_messages).to be_empty
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuses the customer's decline when Shopify will not delete the draft" do
      order, = order_with_draft!(:user_approval)
      refuse_delete!
      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "false" }

      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end
  end

  describe "marking paid" do
    it "deletes an open draft when staff record an in-store payment, so it cannot be paid twice" do
      order, = order_with_draft!(:completed)
      session_login!(staff)
      patch job_order_paid_path(order), params: { paid: "true" }

      expect(status_names(order).last).to eq("Paid (Waiting for Pick-Up)")
      expect(shopify_ops).to eq(%w[getDraftOrder draftOrderDelete])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "keeps a draft Shopify reports COMPLETED (the customer paid through it)" do
      order, = order_with_draft!(:completed)
      shopify.draft_status = "COMPLETED"
      session_login!(staff)
      patch job_order_paid_path(order), params: { paid: "true" }

      expect(status_names(order).last).to eq("Paid (Waiting for Pick-Up)")
      expect(shopify_ops).to eq(["getDraftOrder"])
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end

    it "clears the id of a draft Shopify no longer has with one Shopify call" do
      order, = order_with_draft!(:completed)
      shopify.draft_missing = true
      session_login!(staff)
      patch job_order_paid_path(order), params: { paid: "true" }

      expect(status_names(order).last).to eq("Paid (Waiting for Pick-Up)")
      expect(shopify_ops).to eq(["getDraftOrder"])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "refuses to record the payment when Shopify cannot be asked about the draft" do
      order, = order_with_draft!(:completed)
      shopify.status = 502
      session_login!(staff)
      patch job_order_paid_path(order), params: { paid: "true" }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.draft_not_voidable"))
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end

    # Entering PAID already confirmed the stored draft COMPLETED or removed it, so PAID -> PICKED_UP asks Shopify
    # nothing: staff can record pick-ups during a Shopify outage. Legacy rows are fixed by
    # job_orders:retire_stale_drafts, not on the pick-up.
    it "records a pick-up without any Shopify call, even during an outage" do
      order, = order_with_draft!(:paid)
      shopify.status = 502
      session_login!(staff)
      patch job_order_picked_up_path(order), params: { picked_up: "true" }

      expect(status_names(order).last).to eq("Picked-Up")
      expect(shopify.calls).to be_empty
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end

    # Round 2 review 8: one fail-closed conversion (JobOrder#shopify_fail_closed) for every Shopify call behind a
    # status decision: a raised timeout refuses the change with the draft message, never a 500.
    it "refuses to record the payment when the draft check times out" do
      order, = order_with_draft!(:completed)
      allow(shopify).to receive(:query).and_raise(Net::ReadTimeout)
      session_login!(staff)
      patch job_order_paid_path(order), params: { paid: "true" }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.draft_not_voidable"))
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
    end

    it "refuses a decline when the delete times out" do
      order, = order_with_draft!(:completed)
      allow(shopify).to receive(:query).and_raise(Net::ReadTimeout)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "false", job_order: { staff_comments: "" } }

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.status_change.draft_not_voidable"))
      expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    end
  end

  describe "re-quoting" do
    it "voids the draft even when the new quote has the same prices (the customer approves again)" do
      order, task = order_with_draft!(:completed)
      session_login!(staff)
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task.id}" => "29.99",
                                                   job_order: { staff_comments: "" } }

      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(shopify_ops).to eq(%w[draftOrderDelete])
      expect(order.reload.shopify_draft_order_id).to be_nil
    end
  end

  it "keeps the draft when an order moves into COMPLETED (waiting for payment)" do
    order, = order_with_draft!(:being_processed)
    session_login!(staff)
    patch job_order_processed_path(order), params: { completed: "true" }

    expect(status_names(order).last).to eq("Completed (Waiting for Payment)")
    expect(shopify.calls).to be_empty
    expect(order.reload.shopify_draft_order_id).to eq(draft_id)
  end

  it "voids the draft on a move into processing" do
    order, = order_with_draft!(:waiting_processed)
    session_login!(staff)
    patch job_order_start_processing_path(order), params: { start_processing: "true" }

    expect(status_names(order).last).to eq("Currently being Processed")
    expect(order.reload.shopify_draft_order_id).to be_nil
  end
end
