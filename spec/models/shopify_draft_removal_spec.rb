# frozen_string_literal: true

require "rails_helper"

# The one classification of a Shopify draft delete, shared by JobOrder::DraftDeletion and LockerRental.
RSpec.describe ShopifyConcern::DraftRemoval do
  let!(:fake) { stub_shopify_admin! }
  let(:gid) { fake.draft_id }

  it ":deleted when Shopify confirms the delete (one call, no fetch)" do
    result = described_class.call(gid)
    expect(result.outcome).to eq(:deleted)
    expect(fake.calls.size).to eq(1)
  end

  context "when Shopify refuses (200, userErrors, no deletedId)" do
    before { fake.delete_user_errors = [{ "field" => "id", "message" => "nope" }] }

    it ":gone when the draft no longer exists" do
      fake.missing_ids << gid
      expect(described_class.call(gid).outcome).to eq(:gone)
    end

    it ":completed when the draft is paid" do
      fake.draft_statuses[gid] = "COMPLETED"
      expect(described_class.call(gid).outcome).to eq(:completed)
    end

    it ":open (with Shopify's userErrors) when the draft is still there and unpaid" do
      result = described_class.call(gid)
      expect(result.outcome).to eq(:open)
      expect(result.user_errors.map { |e| e["message"] }).to eq(["nope"])
    end

    it "raises Unanswered when the check gets no answer" do
      fake.on_query = ->(query, _) { fake.status = 500 if query.include?("getDraftOrder") }
      expect { described_class.call(gid) }.to raise_error(described_class::Unanswered, /did not answer/)
    end
  end

  it "propagates a failed delete call (never reads as gone or paid)" do
    fake.status = 500
    expect { described_class.call(gid) }.to raise_error(/Received HTTP 500/)
  end
end
