# frozen_string_literal: true

require "rails_helper"

# LockerRental::DraftSweep: a locker draft is created on Shopify before its id is stored, so the open drafts that
# carry a locker marker are reconciled against the rentals. Shopify is stubbed (FakeShopifyAdmin).
RSpec.describe LockerRental::DraftSweep, type: :model do
  include ShopSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:shopify) { stub_shopify_admin! }
  let(:operating_tag) { LockerRental.draft_order_operating_tag }
  let(:old) { 2.hours.ago.iso8601 }
  let(:gid) { "gid://shopify/DraftOrder/1" }

  around { |example| travel_to(Time.zone.local(2026, 6, 1, 12)) { example.run } }

  def rental_with_draft!(stored: nil, state: :await_payment)
    create(:locker_rental, :await_payment).tap do |r|
      r.update_columns(state: state.to_s, shopify_draft_order_id: stored)
    end
  end

  def draft_node(id, rental, status: "OPEN", tags: nil, created_at: old)
    { "id" => id, "status" => status, "tags" => tags || [operating_tag, "locker_rental:#{rental.id}"], "createdAt" => created_at }
  end

  def sweep(*nodes, pages: nil)
    shopify.draft_pages = pages || [nodes]
    described_class.run
  end

  describe "tagging" do
    it "marks a draft created for a checkout with the operating tag and the rental's marker" do
      rental = create(:locker_rental, :await_payment)
      rental.checkout_link

      create_call = shopify.calls.find { |c| c[:query].include?("draftOrderCreate") }
      expect(create_call[:variables].dig(:input, :tags)).to eq([operating_tag, "locker_rental:#{rental.id}"])
      expect(LockerRental.marked_for?(create_call[:variables].dig(:input, :tags), rental.id)).to be(true)
      expect(LockerRental.marked_for?([operating_tag, "locker_rental:#{rental.id + 1}"], rental.id)).to be(false)
    end
  end

  describe "listing" do
    it "asks Shopify for this environment's payable locker drafts only" do
      sweep
      listing = shopify.calls.find { |c| c[:query].include?("shopifyOpenDrafts") }
      expect(listing[:variables][:query]).to eq("(status:open OR status:invoice_sent) tag:#{operating_tag}")
    end
  end

  describe "drafts it closes" do
    it "deletes an old draft no rental stores, and leaves the rental row as it is" do
      rental = rental_with_draft!
      report = sweep(draft_node(gid, rental))

      expect(shopify.deleted_ids).to eq([gid])
      expect(report.counts[:deleted]).to eq(1)
      expect(report).to be_ok
      expect(rental.reload).to be_await_payment
    end

    it "deletes the old draft of a cancelled rental and forgets the id the rental stored for it" do
      rental = rental_with_draft!(stored: gid, state: :cancelled)
      report = sweep(draft_node(gid, rental))

      expect(shopify.deleted_ids).to eq([gid])
      expect(rental.reload.shopify_draft_order_id).to be_nil
      expect(rental).to be_cancelled
      expect(report.counts[:deleted]).to eq(1)
    end

    it "deletes an old draft when the rental waiting for payment stores a different one, and keeps that one" do
      rental = rental_with_draft!(stored: "gid://shopify/DraftOrder/2")
      sweep(draft_node(gid, rental))

      expect(shopify.deleted_ids).to eq([gid])
      expect(rental.reload.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/2")
    end

    it "deletes the draft of a rental whose row is gone" do
      rental = rental_with_draft!
      node = draft_node(gid, rental)
      LockerRental.where(id: rental.id).delete_all
      report = sweep(node)

      expect(shopify.deleted_ids).to eq([gid])
      expect(report.counts[:deleted]).to eq(1)
    end

    it "counts a draft Shopify no longer has as cleared, so a second run changes nothing" do
      rental = rental_with_draft!
      node = draft_node(gid, rental)
      sweep(node)
      shopify.missing_ids << gid
      report = sweep(node)

      expect(shopify.deleted_ids).to eq([gid])
      expect(report.counts).to include(deleted: 0, cleared: 1)
      expect(report).to be_ok
    end
  end

  describe "drafts it leaves alone" do
    it "keeps the draft a rental waiting for payment stores" do
      rental = rental_with_draft!(stored: gid)
      report = sweep(draft_node(gid, rental))

      expect(shopify.deleted_ids).to be_empty
      expect(report.counts[:kept]).to eq(1)
      expect(rental.reload.shopify_draft_order_id).to eq(gid)
    end

    it "keeps a draft younger than the minimum age, which its creator may be about to store" do
      rental = rental_with_draft!
      report = sweep(draft_node(gid, rental, created_at: 10.minutes.ago.iso8601))

      expect(shopify.deleted_ids).to be_empty
      expect(report.counts).to include(kept: 0, deleted: 0)
    end

    it "keeps a draft whose creation time is unknown" do
      rental = rental_with_draft!
      report = sweep(draft_node(gid, rental, created_at: nil))

      expect(shopify.deleted_ids).to be_empty
      expect(report).to be_ok
    end

    it "does not touch a paid draft, listed or found paid when it is fetched" do
      rental = rental_with_draft!
      sweep(draft_node(gid, rental, status: "COMPLETED"))
      shopify.draft_statuses[gid] = "COMPLETED"
      report = sweep(draft_node(gid, rental))

      expect(shopify.deleted_ids).to be_empty
      expect(report.counts[:kept]).to eq(1)
    end

    it "does not touch a draft without a locker marker, or another environment's draft, and counts the first" do
      rental = rental_with_draft!
      report = sweep(draft_node(gid, rental, tags: [operating_tag]),
                     draft_node("gid://shopify/DraftOrder/2", rental, tags: ["makerepo_other_locker", "locker_rental:#{rental.id}"]),
                     draft_node("gid://shopify/DraftOrder/3", rental, tags: [operating_tag, "job_order:#{rental.id}"]))

      expect(shopify.deleted_ids).to be_empty
      expect(report.counts[:unmarked]).to eq(2)
    end

    it "refuses to delete a draft whose tags do not name the rental when it is fetched" do
      rental = rental_with_draft!
      listed = draft_node(gid, rental)
      shopify.on_query = ->(q, _v) { listed["tags"] = [operating_tag, "locker_rental:#{rental.id + 1}"] if q.include?("getDraftOrder") }
      allow(Rails.error).to receive(:report)
      report = sweep(listed)

      expect(shopify.deleted_ids).to be_empty
      expect(report).not_to be_ok
      expect(report.unresolved.first).to include("locker rental ##{rental.id} (draft_not_voidable)")
    end

    it "lists a draft Shopify will not delete as unresolved and keeps the id" do
      rental = rental_with_draft!(stored: gid, state: :cancelled)
      shopify.delete_user_errors = [{ "field" => "id", "message" => "Draft order is locked" }]
      allow(Rails.error).to receive(:report)
      report = sweep(draft_node(gid, rental))

      expect(report.unresolved_gids).to eq([gid])
      expect(rental.reload.shopify_draft_order_id).to eq(gid)
    end
  end

  describe "the kill switch" do
    it "deletes nothing when more drafts are orphans than the cap" do
      stub_const("LockerRental::DraftSweep::MAX_DELETES", 1)
      rentals = Array.new(3) { rental_with_draft! }
      allow(Rails.error).to receive(:report)
      report = sweep(*rentals.each_with_index.map { |r, i| draft_node("gid://shopify/DraftOrder/#{i + 1}", r) })

      expect(shopify.deleted_ids).to be_empty
      expect(report.unresolved.first).to include("NOTHING was deleted", "LockerRental::DraftSweep.run(max_deletes: 3)")
    end
  end

  it "runs beside a job-order sweep: each takes its own lock" do
    expect(described_class::LOCK_KEY).not_to eq(JobOrder::DraftSweep::LOCK_KEY)
  end
end
