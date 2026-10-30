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

  # stdout of the task (its per-order warnings go to stderr, kept out of the test output); the exit status of the
  # run is in `exit_status` (nil: the task finished normally)
  attr_reader :exit_status, :warnings

  def run_task
    out = StringIO.new
    err = StringIO.new
    original = [$stdout, $stderr]
    $stdout = out
    $stderr = err
    @exit_status = nil
    begin
      Rake::Task["job_orders:retire_stale_drafts"].invoke
    rescue SystemExit => e
      @exit_status = e.status
    end
    @warnings = err.string
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
    order = order_with_draft!(:picked_up)
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
    expect(exit_status).to eq(1)
    expect(warnings).to include("draft_not_voidable")
  end

  it "exits 0 when nothing is unresolved" do
    order_with_draft!(:picked_up)
    run_task
    expect(exit_status).to be_nil
  end

  # the run goes on past every kind of per-order failure, and lists each one (the same results as a transition)
  describe "per-order failures are results, listed, and the run goes on" do
    let!(:first) { order_with_draft!(:picked_up) }
    let!(:second) { order_with_draft!(:picked_up) }

    def fail_for!(order)
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        raise yield if m.receiver.id == order.id

        m.call(*args)
      end
    end

    {
      "a lock wait timeout (busy)" => [ActiveRecord::LockWaitTimeout, "busy"],
      "a deadlock" => [ActiveRecord::Deadlocked, "deadlock"],
      "an order deleted meanwhile" => [ActiveRecord::RecordNotFound, "order_missing"]
    }.each do |label, (error, reason)|
      it "#{label} on the first order: listed (#{reason}), the second is still settled" do
        fail_for!(first) { error }
        out = run_task

        expect(out).to include("unresolved: 1 (#{first.id})").and include("deleted: 1")
        expect(warnings).to include(reason)
        expect(second.reload.shopify_draft_order_id).to be_nil
        expect(first.reload.shopify_draft_order_id).to eq(draft_id)
        expect(exit_status).to eq(1)
      end
    end

    it "an unexpected exception is reported and listed, and the run goes on" do
      expect(Rails.error).to receive(:report).with(an_instance_of(NoMethodError), hash_including(handled: true)).once
      fail_for!(first) { NoMethodError.new("boom") }
      out = run_task

      expect(out).to include("unresolved: 1 (#{first.id})").and include("deleted: 1")
      expect(warnings).to include("unexpected").and include("boom")
      expect(second.reload.shopify_draft_order_id).to be_nil
      expect(exit_status).to eq(1)
    end

    it "a Deadlocked is reported to the error reporter (a lock-order bug), a busy row is not" do
      fail_for!(first) { ActiveRecord::Deadlocked }
      expect(Rails.error).to receive(:report).with(an_instance_of(ActiveRecord::Deadlocked), hash_including(handled: true)).once
      run_task
    end
  end

  # A deleted order is not payable whatever its status was: its draft is settled even in COMPLETED
  describe "a soft-deleted order" do
    it "has its open draft deleted even when it was waiting for payment (COMPLETED)" do
      order = order_with_draft!(:completed)
      order.update_column(:is_deleted, true)
      out = run_task

      expect(order.reload.shopify_draft_order_id).to be_nil
      expect(shopify.calls.size).to eq(1)
      expect(out).to include("deleted: 1")
    end

    it "refuses, and lists, a draft Shopify reports paid (COMPLETED): the delete would lose the payment record" do
      order = order_with_draft!(:completed)
      order.update_column(:is_deleted, true)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete a completed draft order" }]
      shopify.draft_status = "COMPLETED"
      out = run_task

      expect(order.reload.shopify_draft_order_id).to eq(draft_id)
      expect(out).to include("unresolved: 1 (#{order.id})")
      expect(exit_status).to eq(1)
    end
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
