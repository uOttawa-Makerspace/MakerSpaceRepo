# frozen_string_literal: true

require "rails_helper"

# JobOrder::DraftSweep: Shopify cannot roll a draft create back, so the open drafts that carry a job-order marker
# are reconciled against the database. Shopify is stubbed (FakeShopifyAdmin).
RSpec.describe JobOrder::DraftSweep, type: :model do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let!(:shopify) { stub_shopify_admin! }
  let(:operating_tag) { JobOrder.draft_order_operating_tag }

  before { seed_job_statuses! }

  def order_with_draft!(status_key = :completed, stored: nil)
    make_job_order!(owner: owner, status_key: status_key).tap { |o| o.update_column(:shopify_draft_order_id, stored) if stored }
  end

  def draft_node(gid, order, status: "OPEN", tags: nil)
    { "id" => gid, "status" => status, "tags" => tags || [operating_tag, "job_order:#{order.id}"] }
  end

  def sweep(*nodes, pages: nil)
    shopify.draft_pages = pages || [nodes]
    described_class.run
  end

  it "deletes the orphan draft of a COMPLETED order whose stored draft is a different one" do
    order = order_with_draft!(stored: "gid://shopify/DraftOrder/2")
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/2")
    expect(report.counts[:deleted]).to eq(1)
    expect(report).to be_ok
  end

  it "deletes the draft of an order that has none stored (a create whose transaction rolled back)" do
    order = order_with_draft!
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(report.counts[:deleted]).to eq(1)
  end

  it "deletes the draft of a deleted order, and clears the id the order stored for it" do
    order = order_with_draft!(stored: "gid://shopify/DraftOrder/1")
    order.update_column(:is_deleted, true)
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(order.reload.shopify_draft_order_id).to be_nil
    expect(report.counts[:deleted]).to eq(1)
  end

  it "deletes the draft of an order whose row is gone" do
    order = order_with_draft!
    gone = draft_node("gid://shopify/DraftOrder/1", order)
    order.job_order_statuses.delete_all
    order.delete
    report = sweep(gone)

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(report).to be_ok
  end

  it "counts a delete as deleted when the order row disappears after the listing" do
    order = order_with_draft!(stored: "gid://shopify/DraftOrder/1")
    allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::RecordNotFound)
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(report.counts[:deleted]).to eq(1)
    expect(report).to be_ok
  end

  it "keeps a draft whose order moved to COMPLETED (keeping its stored id) after the sweep decided it was an orphan" do
    order = order_with_draft!(:staff_approval, stored: "gid://shopify/DraftOrder/1")
    allow(JobOrder).to receive(:find_by).and_wrap_original do |m, *args, **kw|
      m.call(*args, **kw).tap { |o| o.job_order_statuses.create!(job_status: JobStatus::COMPLETED, user: owner) }
    end
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to be_empty
    expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
    expect(report.counts).to include(kept: 1, deleted: 0)
  end

  it "fetches and deletes only inside the order's row lock" do
    order = order_with_draft!(:staff_approval, stored: "gid://shopify/DraftOrder/1")
    locked = []
    allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original { |m, *a| locked << true; m.call(*a) }
    shopify.on_query = ->(q, _v) { expect(locked).not_to be_empty unless q.include?("jobOrderOpenDrafts") }
    sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
  end

  it "keeps the current draft of an order waiting for payment" do
    order = order_with_draft!(stored: "gid://shopify/DraftOrder/1")
    report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

    expect(shopify.deleted_ids).to be_empty
    expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
    expect(report.counts[:kept]).to eq(1)
  end

  %i[draft staff_approval being_processed user_approval paid picked_up].each do |status_key|
    it "deletes the open draft of an order in #{status_key} (not payable), clearing the stored id" do
      order = order_with_draft!(status_key, stored: "gid://shopify/DraftOrder/1")
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
      expect(order.reload.shopify_draft_order_id).to be_nil
      expect(report.counts[:deleted]).to eq(1)
    end
  end

  describe "a paid (COMPLETED) draft is never deleted" do
    it "is not even listed as a candidate" do
      order = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order, status: "COMPLETED"))

      expect(shopify.deleted_ids).to be_empty
      expect(shopify.calls.size).to eq(1) # the listing only
      expect(report.counts.values.sum).to eq(0)
    end

    it "is kept when it was paid between the listing and the check" do
      order = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      shopify.draft_statuses["gid://shopify/DraftOrder/1"] = "COMPLETED"
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(shopify.deleted_ids).to be_empty
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
      expect(report.counts[:kept]).to eq(1)
    end
  end

  describe "drafts that are not job-order drafts of this environment" do
    it "leaves a draft without the marker untouched" do
      order = order_with_draft!(:paid)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order, tags: [operating_tag]))

      expect(shopify.calls.size).to eq(1)
      expect(report.counts[:unmarked]).to eq(1)
    end

    it "leaves locker and membership drafts untouched" do
      order = order_with_draft!(:paid)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order, tags: [LockerRental.draft_order_operating_tag]),
                     draft_node("gid://shopify/DraftOrder/2", order, tags: [Membership.draft_order_operating_tag]))

      expect(shopify.calls.size).to eq(1)
      expect(report.counts.values.sum).to eq(0)
    end

    it "leaves a draft of another environment untouched" do
      order = order_with_draft!(:paid)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order, tags: ["makerepo_production_job_order", "job_order:#{order.id}"]))

      expect(shopify.calls.size).to eq(1)
      expect(report.counts.values.sum).to eq(0)
    end

    it "counts an unmarked draft listed on two pages once" do
      order = order_with_draft!(:paid)
      node = draft_node("gid://shopify/DraftOrder/1", order, tags: [operating_tag])
      report = sweep(pages: [[node], [node]])

      expect(report.counts[:unmarked]).to eq(1)
    end

    it "leaves a draft with two different markers untouched" do
      order = order_with_draft!(:paid)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order, tags: [operating_tag, "job_order:1", "job_order:2"]))

      expect(shopify.calls.size).to eq(1)
      expect(report.counts[:unmarked]).to eq(1)
    end
  end

  it "asks Shopify for this environment's unpaid (OPEN and INVOICE_SENT) job-order drafts only" do
    sweep
    variables = shopify.calls.first[:variables]

    expect(variables[:query]).to eq("(status:open OR status:invoice_sent) tag:#{operating_tag}")
  end

  it "deletes an orphan INVOICE_SENT draft too, and keeps the current one" do
    orphan = order_with_draft!
    current = order_with_draft!(stored: "gid://shopify/DraftOrder/2")
    report = sweep(draft_node("gid://shopify/DraftOrder/1", orphan, status: "INVOICE_SENT"),
                   draft_node("gid://shopify/DraftOrder/2", current, status: "INVOICE_SENT"))

    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    expect(report.counts).to include(deleted: 1, kept: 1)
  end

  it "deletes the INVOICE_SENT draft of an order whose row is gone" do
    order = order_with_draft!
    gone = draft_node("gid://shopify/DraftOrder/1", order, status: "INVOICE_SENT")
    order.job_order_statuses.delete_all
    order.delete

    expect(sweep(gone)).to be_ok
    expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
  end

  it "keeps the stored id of a draft Shopify reports paid, and clears the id of a deleted one" do
    paid = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
    shopify.draft_statuses["gid://shopify/DraftOrder/1"] = "COMPLETED"
    open_one = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/2")
    sweep(draft_node("gid://shopify/DraftOrder/1", paid), draft_node("gid://shopify/DraftOrder/2", open_one))

    expect(paid.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
    expect(open_one.reload.shopify_draft_order_id).to be_nil
  end

  describe "an order without a status never keeps a draft" do
    it "deletes the draft of a status-less order even when the JobStatus constants are nil (unseeded)" do
      order = order_with_draft!(stored: "gid://shopify/DraftOrder/1")
      order.job_order_statuses.delete_all
      stub_const("JobStatus::COMPLETED", nil)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
      expect(report.counts[:kept]).to eq(0)
    end
  end

  describe "the listing is guarded" do
    it "stops when the cursor repeats, reports it as unresolved and still reconciles what it read" do
      order = order_with_draft!
      shopify.fixed_cursor = "same"
      report = sweep(pages: [[draft_node("gid://shopify/DraftOrder/1", order)]])

      expect(report.unresolved.first).to include("cursor", "repeated")
      expect(shopify.calls.count { |c| c[:query].include?("jobOrderOpenDrafts") }).to eq(2)
      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
    end

    it "stops at MAX_PAGES and says so" do
      stub_const("JobOrder::DraftSweep::MAX_PAGES", 3)
      report = sweep(pages: Array.new(6) { [] })

      expect(shopify.calls.count { |c| c[:query].include?("jobOrderOpenDrafts") }).to eq(3)
      expect(report.unresolved.first).to include("more than 3 pages")
    end

    it "handles a draft listed twice once" do
      order = order_with_draft!
      node = draft_node("gid://shopify/DraftOrder/1", order)
      report = sweep(pages: [[node], [node]])

      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
      expect(report).to be_ok
    end
  end

  describe "concurrent sweeps" do
    it "is skipped while another session holds the sweep lock" do
      other = PG.connect(**ActiveRecord::Base.connection_db_config.configuration_hash.slice(:host, :port, :dbname, :database, :user, :username, :password).transform_keys { |k| { database: :dbname, username: :user }.fetch(k, k) }.compact)
      begin
        expect(other.exec("SELECT pg_try_advisory_lock(#{described_class::LOCK_KEY})").getvalue(0, 0)).to eq("t")
        order = order_with_draft!
        report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

        expect(report.skipped).to be(true)
        expect(shopify.calls).to be_empty
      ensure
        other.close
      end
    end

    it "releases the lock after a run" do
      sweep
      expect(sweep.skipped).to be(false)
    end

    it "counts a draft another sweep deleted first as cleared, not as an error" do
      order = order_with_draft!
      shopify.lose_delete_race = :gone
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(report).to be_ok
      expect(report.counts[:cleared]).to eq(1)
    end

    it "counts a draft paid between the fetch and the delete as kept" do
      order = order_with_draft!(stored: "gid://shopify/DraftOrder/2")
      shopify.lose_delete_race = :paid
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(report).to be_ok
      expect(report.counts[:kept]).to eq(1)
    end
  end

  describe "the kill switch" do
    let(:nodes) { Array.new(3) { |i| draft_node("gid://shopify/DraftOrder/#{i + 1}", order_with_draft!) } }

    it "deletes NOTHING when the orphans exceed the cap, and says how to override" do
      shopify.draft_pages = [nodes]
      report = described_class.run(max_deletes: 2)

      expect(shopify.deleted_ids).to be_empty
      expect(shopify.calls.size).to eq(1) # the listing only
      expect(report).not_to be_ok
      expect(report.unresolved.first).to include("3 orphan", "cap of 2", "NOTHING", "CONFIRM_MAX_DELETES=3")
    end

    it "counts only the drafts the database does not back" do
      current = order_with_draft!(stored: "gid://shopify/DraftOrder/9")
      shopify.draft_pages = [nodes + [draft_node("gid://shopify/DraftOrder/9", current)]]
      report = described_class.run(max_deletes: 3)

      expect(shopify.deleted_ids.size).to eq(3)
      expect(report).to be_ok
    end

    it "proceeds with an explicit override" do
      shopify.draft_pages = [nodes]
      report = described_class.run(max_deletes: 3)

      expect(shopify.deleted_ids.size).to eq(3)
      expect(report).to be_ok
    end

    it "defaults to 200" do
      expect(described_class::MAX_DELETES).to eq(200)
    end
  end

  describe "reporting" do
    let(:reports) { [] }

    before { allow(Rails.error).to receive(:report) { |error, **kw| reports << [error, kw] } }

    it "reports a run with unresolved drafts once, with a stable message and the gids in the context" do
      first = order_with_draft!
      second = order_with_draft!
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]
      sweep(draft_node("gid://shopify/DraftOrder/1", first), draft_node("gid://shopify/DraftOrder/2", second))

      expect(reports.size).to eq(1)
      error, kw = reports.first
      expect(error.message).to eq("job order draft sweep: unresolved drafts")
      expect(kw[:context]).to include(unresolved_count: 2, unresolved_draft_order_ids: %w[gid://shopify/DraftOrder/1 gid://shopify/DraftOrder/2])
    end

    it "keeps the message stable whichever drafts are unresolved" do
      messages = %w[1 2].map do |n|
        reports.clear
        shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete #{n}" }]
        sweep(draft_node("gid://shopify/DraftOrder/#{n}", order_with_draft!))
        reports.first.first.message
      end

      expect(messages.uniq).to eq(["job order draft sweep: unresolved drafts"])
    end

    it "reports nothing when everything is resolved" do
      sweep
      expect(reports).to be_empty
    end

    it "reports an unexpected exception on its own, with the gid, plus the run summary" do
      order = order_with_draft!
      boom = ArgumentError.new("boom")
      allow_any_instance_of(JobOrder).to receive(:reconcile_orphan_draft!).and_raise(boom)
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(report.unresolved.first).to include("unexpected", "boom")
      expect(reports.size).to eq(2)
      expect(reports.first.first).to equal(boom)
      expect(reports.first.last[:context]).to include(draft_order_id: "gid://shopify/DraftOrder/1", job_order_id: order.id)
      expect(reports.last.first.message).to eq("job order draft sweep: unresolved drafts")
    end

    it "reports a deadlock on its own, with the real exception, plus the run summary" do
      order = order_with_draft!
      allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::Deadlocked, "deadlock detected")
      report = sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(report.unresolved.first).to include("deadlock")
      expect(reports.size).to eq(2)
      expect(reports.first.first).to be_a(ActiveRecord::Deadlocked)
      expect(reports.first.last[:context]).to include(draft_order_id: "gid://shopify/DraftOrder/1")
    end

    it "does not report a busy order or a refused delete individually" do
      order = order_with_draft!
      allow_any_instance_of(JobOrder).to receive(:lock!).and_raise(ActiveRecord::LockWaitTimeout)
      sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(reports.size).to eq(1)
    end
  end

  it "follows the pagination to the last page" do
    orders = Array.new(3) { order_with_draft! }
    nodes = orders.each_with_index.map { |o, i| draft_node("gid://shopify/DraftOrder/#{i + 1}", o) }
    report = sweep(pages: [[nodes[0]], [nodes[1]], [nodes[2]]])

    expect(shopify.deleted_ids).to eq(%w[gid://shopify/DraftOrder/1 gid://shopify/DraftOrder/2 gid://shopify/DraftOrder/3])
    expect(shopify.calls.first[:variables][:after]).to be_nil
    expect(report.counts[:deleted]).to eq(3)
  end

  describe "Shopify errors fail closed" do
    it "an unreadable listing is unresolved and deletes nothing" do
      shopify.status = 502
      report = described_class.run

      expect(report).not_to be_ok
      expect(report.unresolved.first).to include("listing open drafts")
    end

    it "a draft Shopify will not delete is unresolved, the next one is still reconciled" do
      first = order_with_draft!
      second = order_with_draft!
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]
      report = sweep(draft_node("gid://shopify/DraftOrder/1", first), draft_node("gid://shopify/DraftOrder/2", second))

      expect(report.unresolved.size).to eq(2)
      expect(report.unresolved.first).to include("gid://shopify/DraftOrder/1", "draft_not_voidable", "cannot delete")
      expect(shopify.deleted_ids.size).to eq(2) # both were attempted
    end

    it "a busy order is unresolved and the run goes on" do
      first = order_with_draft!
      second = order_with_draft!
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        raise ActiveRecord::LockWaitTimeout if m.receiver.id == first.id

        m.call(*args)
      end
      report = sweep(draft_node("gid://shopify/DraftOrder/1", first), draft_node("gid://shopify/DraftOrder/2", second))

      expect(report.unresolved.size).to eq(1)
      expect(report.unresolved.first).to include("busy")
      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/2"])
    end
  end

  describe "one rule for draft status and for the paid settle" do
    it "knows the payable statuses and the paid one in one place" do
      expect(JobOrder::PAYABLE_DRAFT_STATUSES).to eq(%w[OPEN INVOICE_SENT])
      expect(JobOrder.draft_paid?("status" => "COMPLETED")).to be(true)
      expect(JobOrder.draft_paid?("status" => "INVOICE_SENT")).to be(false)
    end

    it "settles a paid-destination order through the one paid-settle rule, dropping the id" do
      order = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      expect(JobOrder.const_get(:DraftDeletion)).to receive(:delete_unless_completed!).with("gid://shopify/DraftOrder/1").and_call_original

      expect(order.send(:settle_for_paid_order)).to eq(:deleted)
      expect(order.reload.shopify_draft_order_id).to be_nil
    end

    it "keeps the id of a paid draft and drops that of a vanished one" do
      order = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      shopify.draft_statuses["gid://shopify/DraftOrder/1"] = "COMPLETED"
      expect(order.send(:settle_for_paid_order)).to eq(:kept)
      expect(order.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")

      shopify.missing_ids << "gid://shopify/DraftOrder/1"
      expect(order.send(:settle_for_paid_order)).to eq(:cleared)
      expect(order.reload.shopify_draft_order_id).to be_nil
    end
  end

  describe "the gid-level Shopify calls are not part of the models' API" do
    it "are not class methods of JobOrder, LockerRental or Membership" do
      [JobOrder, LockerRental, Membership].each do |model|
        %i[delete_shopify_draft_order fetch_shopify_draft_order_result shopify_admin_client delete_draft_unless_completed!
           fetch_draft_or_raise start_shopify_session].each do |name|
          expect(model).not_to respond_to(name)
        end
      end
    end

    it "gives LockerRental and Membership no delete-by-gid method at all" do
      [LockerRental, Membership].each do |model|
        names = model.public_methods + model.new.public_methods
        expect(names.grep(/delete.*draft|draft.*delete|reconcile_orphan/) - %i[destroy_shopify_draft_order]).to be_empty
      end
    end

    it "keeps the deletion helper out of reach of everything but JobOrder" do
      expect { JobOrder::DraftDeletion }.to raise_error(NameError, /private constant/)
    end

    it "uses one Admin client builder for ShopifyService and the draft calls" do
      expect(ShopifyConcern::DraftOrders).to receive(:client).and_return(:client)
      expect(ShopifyService.admin_client).to eq(:client)
    end

    it "builds the client for a draft create through the one builder" do
      order = order_with_draft!
      order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 5, service_price: 0, service_quantity: 0).save!
      expect(ShopifyConcern::DraftOrders).to receive(:client).at_least(:once).and_call_original

      expect(order.reload.checkout_link).to be_ok
    end
  end

  describe "the marker on a created draft" do
    it "tags the draft with the environment's operating tag and the order's marker" do
      order = order_with_draft!
      order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 5, service_price: 0, service_quantity: 0).save!

      expect(order.reload.checkout_link).to be_ok
      create_call = shopify.calls.find { |c| c[:query].include?("draftOrderCreate") }

      expect(create_call[:variables].dig(:input, :tags)).to eq([operating_tag, "job_order:#{order.id}"])
    end
  end
end
