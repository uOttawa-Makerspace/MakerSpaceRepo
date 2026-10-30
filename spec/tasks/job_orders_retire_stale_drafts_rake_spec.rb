# frozen_string_literal: true

require "rails_helper"
require "rake"

# One-off clean-up of orders written before transitions settled their Shopify draft: the same rule as a
# transition into the order's current status (JobOrder#settle_draft_order!), each order under its row lock.
RSpec.describe "job_orders:retire_stale_drafts", type: :model do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:shopify) { stub_shopify_admin! }
  let(:draft_id) { "gid://shopify/DraftOrder/9001" }

  before do
    seed_job_statuses!
    Rails.application.load_tasks unless Rake::Task.task_defined?("job_orders:retire_stale_drafts")
    Rake::Task["job_orders:retire_stale_drafts"].reenable
  end

  def order_with_draft!(status_key)
    make_job_order!(owner: owner, status_key: status_key).tap { |o| o.update_column(:shopify_draft_order_id, draft_id) }
  end

  # stdout of the task (its per-order warnings go to stderr, kept out of the test output)
  def run_task
    out = StringIO.new
    original = [$stdout, $stderr]
    $stdout = out
    $stderr = StringIO.new
    Rake::Task["job_orders:retire_stale_drafts"].invoke
    out.string
  ensure
    $stdout, $stderr = original
  end

  it "deletes an open draft on a Picked-Up order" do
    order = order_with_draft!(:picked_up)
    out = run_task

    expect(order.reload.shopify_draft_order_id).to be_nil
    expect(out).to include("deleted: 1").and include("unresolved: 0")
  end

  it "keeps a COMPLETED draft" do
    order = order_with_draft!(:picked_up)
    shopify.draft_status = "COMPLETED"
    out = run_task

    expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    expect(out).to include("kept: 1")
  end

  it "clears the id of a draft Shopify no longer has, with one Shopify call" do
    order = order_with_draft!(:being_processed)
    shopify.draft_missing = true
    out = run_task

    expect(order.reload.shopify_draft_order_id).to be_nil
    expect(shopify.calls.size).to eq(1)
    expect(out).to include("cleared: 1")
  end

  it "lists the orders Shopify could not resolve and leaves them untouched" do
    order = order_with_draft!(:picked_up)
    shopify.status = 502
    out = run_task

    expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    expect(out).to include("unresolved: 1 (#{order.id})")
  end

  it "leaves an order waiting for payment alone, without asking Shopify" do
    order = order_with_draft!(:completed)
    out = run_task

    expect(order.reload.shopify_draft_order_id).to eq(draft_id)
    expect(shopify.calls).to be_empty
    expect(out).to include("skipped: 1")
  end

  it "is idempotent: a rerun finds nothing to do" do
    order_with_draft!(:picked_up)
    run_task
    Rake::Task["job_orders:retire_stale_drafts"].reenable
    shopify.calls.clear
    out = run_task

    expect(shopify.calls).to be_empty
    expect(out).to include("deleted: 0").and include("unresolved: 0")
  end
end
