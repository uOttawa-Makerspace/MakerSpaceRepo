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

  describe "the Shopify calls are made outside the order's lock" do
    it "never calls Shopify inside a transaction the sweep opened" do
      order = order_with_draft!(stored: "gid://shopify/DraftOrder/2")
      baseline = JobOrder.connection.open_transactions
      depths = []
      shopify.on_query = ->(_q, _v) { depths << JobOrder.connection.open_transactions }
      sweep(draft_node("gid://shopify/DraftOrder/1", order))

      expect(shopify.deleted_ids).to eq(["gid://shopify/DraftOrder/1"])
      expect(depths).to all(eq(baseline))
    end

    it "keeps the stored id of a draft Shopify reports paid, and clears the id of a deleted one" do
      paid = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      shopify.draft_statuses["gid://shopify/DraftOrder/1"] = "COMPLETED"
      open_one = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/2")
      sweep(draft_node("gid://shopify/DraftOrder/1", paid), draft_node("gid://shopify/DraftOrder/2", open_one))

      expect(paid.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/1")
      expect(open_one.reload.shopify_draft_order_id).to be_nil
    end
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

  describe "the delete cap" do
    it "stops deleting at the cap, leaves the rest and is unresolved" do
      nodes = Array.new(3) { |i| draft_node("gid://shopify/DraftOrder/#{i + 1}", order_with_draft!) }
      shopify.draft_pages = [nodes]
      report = described_class.run(max_deletes: 2)

      expect(shopify.deleted_ids.size).to eq(2)
      expect(report).not_to be_ok
      expect(report.unresolved.first).to include("cap of 2")
    end

    it "defaults to 200" do
      expect(described_class::MAX_DELETES).to eq(200)
    end
  end

  describe "one report per problem" do
    it "reports a run with unresolved drafts once, naming the drafts" do
      first = order_with_draft!
      second = order_with_draft!
      shopify.delete_user_errors = [{ "field" => "id", "message" => "cannot delete" }]
      reports = []
      allow(Rails.error).to receive(:report) { |*args, **kw| reports << [args, kw] }
      sweep(draft_node("gid://shopify/DraftOrder/1", first), draft_node("gid://shopify/DraftOrder/2", second))

      expect(reports.size).to eq(1)
      expect(reports.first.last.dig(:context, :unresolved_draft_order_ids)).to eq(%w[gid://shopify/DraftOrder/1 gid://shopify/DraftOrder/2])
    end

    it "reports nothing when everything is resolved" do
      expect(Rails.error).not_to receive(:report)
      sweep
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

    it "settles a paid-destination order through JobOrder.delete_draft_unless_completed!, dropping the id" do
      order = order_with_draft!(:paid, stored: "gid://shopify/DraftOrder/1")
      expect(JobOrder).to receive(:delete_draft_unless_completed!).with("gid://shopify/DraftOrder/1").and_call_original

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
        %i[delete_shopify_draft_order fetch_shopify_draft_order_result shopify_admin_client].each do |name|
          expect(model).not_to respond_to(name)
        end
      end
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
