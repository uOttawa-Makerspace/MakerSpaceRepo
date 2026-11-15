# frozen_string_literal: true

require "rails_helper"

# Where a locker rental's pay link comes from: its one open checkout record, claimed before Shopify is asked for a
# draft and tagged on the draft, so a later attempt reuses the draft an earlier one made. Also when a rental starts a
# new term, when Shopify could not settle last term's draft, and when a draft has a status nobody expects.
RSpec.describe "Locker checkout link", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:old_id) { "gid://shopify/DraftOrder/last-term" }
  let(:new_id) { "gid://shopify/DraftOrder/new-term" }
  let(:old_url) { "https://shop.example.test/invoices/old" }
  let(:new_url) { "https://shop.example.test/invoices/new" }
  let!(:fake) do
    stub_shopify_admin!.tap do |f|
      f.draft_id = new_id
      f.invoice_urls.merge!(old_id => old_url, new_id => new_url)
    end
  end

  def log_in!(user, password: "asa32A353#")
    post login_authentication_path, params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
  end

  # A stored draft with its checkout record.
  def with_checkout(rental, gid, status)
    rental.update_column(:shopify_draft_order_id, gid)
    PaymentCheckout.create!(reference: rental, provider: "shopify", provider_id: gid, status: status,
                            term: rental.owned_until&.to_date)
    rental
  end

  def checkouts(rental) = PaymentCheckout.where(reference: rental).order(:id).pluck(:provider_id, :status)

  def claim!(rental) = PaymentCheckout.create!(reference: rental, provider: "shopify", term: rental.owned_until.to_date)

  def tag(checkout) = Payments::ShopifyAdapter.checkout_tag(checkout.id)

  def lookups = fake.calls.count { |c| c[:query].include?("paymentsOpenCheckout") }

  describe "claim first" do
    let(:rental) { create(:locker_rental, :await_payment, rented_by: owner) }

    it "claims the checkout before Shopify is asked, tags the draft with it, and the claim takes the draft" do
      claimed = nil
      fake.on_query = ->(query, _) { claimed ||= checkouts(rental) if query.include?("draftOrderCreate") }

      expect(rental.checkout_link).to eq(new_url)
      expect(claimed).to eq([[nil, "open"]])
      checkout = PaymentCheckout.find_by!(reference: rental)
      expect(fake.created_tags(new_id)).to include(tag(checkout), "locker_rental:#{rental.id}")
      expect(checkouts(rental)).to eq([[new_id, "open"]])
      expect(rental.reload.shopify_draft_order_id).to eq(new_id)
      expect(lookups).to eq(0) # a claim made now has no draft to find
    end

    it "a claim an earlier attempt left reuses the open draft tagged with it" do
      claim = claim!(rental)
      fake.draft_pages = [[{ "id" => old_id, "status" => "OPEN", "tags" => [tag(claim)] }]]

      expect(rental.checkout_link).to eq(old_url)
      expect(fake.created_ids).to be_empty
      expect(checkouts(rental)).to eq([[old_id, "open"]])
      expect(rental.reload.shopify_draft_order_id).to eq(old_id)
    end

    it "a claim with no open tagged draft makes one, tagged with the same claim" do
      claim = claim!(rental)
      fake.draft_pages = [[{ "id" => old_id, "status" => "COMPLETED", "tags" => [tag(claim)] }]]

      expect(rental.checkout_link).to eq(new_url)
      expect(lookups).to eq(1)
      expect(fake.created_tags(new_id)).to include(tag(claim))
      expect(checkouts(rental)).to eq([[new_id, "open"]])
    end

    it "a draft another request gave the same claim meanwhile is kept, never removed" do
      claim = claim!(rental)
      fake.draft_pages = [[{ "id" => old_id, "status" => "OPEN", "tags" => [tag(claim)] }]]
      fake.on_query = lambda do |query, _|
        claim.update_column(:provider_id, old_id) if query.include?("paymentsOpenCheckout")
      end

      expect(rental.checkout_link).to eq(old_url)
      expect(fake.deleted_ids).to be_empty
      expect(rental.reload.shopify_draft_order_id).to eq(old_id)
    end

    it "a stored draft no checkout record names opens its checkout and is served: no second draft" do
      rental.update_column(:shopify_draft_order_id, old_id)

      expect(rental.checkout_link).to eq(old_url)
      expect(fake.created_ids).to be_empty
      expect(checkouts(rental)).to eq([[old_id, "open"]])
    end

    it "a rental cancelled since it was loaded claims nothing and asks Shopify nothing" do
      stale = LockerRental.find(rental.id)
      LockerRental.where(id: rental.id).update_all(state: "cancelled", cancelled_at: Time.current)

      expect(stale.checkout_link).to be_nil
      expect(checkouts(rental)).to be_empty
      expect(fake.calls).to be_empty
    end

    it "a stored draft no checkout record names is not adopted by a rental cancelled since it was loaded" do
      rental.update_column(:shopify_draft_order_id, old_id)
      stale = LockerRental.find(rental.id)
      LockerRental.where(id: rental.id).update_all(state: "cancelled", cancelled_at: Time.current)

      expect(stale.checkout_link).to be_nil
      expect(checkouts(rental)).to be_empty
      expect(fake.calls).to be_empty
    end

    it "a draft the rental may no longer take voids the claim and is removed" do
      fake.on_query = lambda do |query, _|
        LockerRental.where(id: rental.id).update_all(state: "reviewing") if query.include?("draftOrderCreate")
      end

      expect(rental.checkout_link).to be_nil
      expect(fake.deleted_ids).to eq([new_id])
      expect(checkouts(rental)).to eq([[nil, "void"]])
      expect(rental.reload.shopify_draft_order_id).to be_nil
    end
  end

  it "a renewal voids last term's open checkout in its own transaction, even a claim with no draft yet" do
    rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
    claim!(rental)
    log_in!(owner)

    patch renew_locker_rental_path(rental)
    expect(rental.reload.state).to eq("await_payment")
    expect(checkouts(rental)).to eq([[nil, "void"]])
  end

  it "a save that starts no new term keeps the open checkout" do
    rental = with_checkout(create(:locker_rental, :await_payment, rented_by: owner), old_id, :open)
    log_in!(staff)

    patch locker_rental_path(rental), params: { locker_rental: { notes: "moved" } }
    expect(rental.reload.notes).to eq("moved")
    expect(checkouts(rental)).to eq([[old_id, "open"]])
  end

  it "a renewal whose last-term draft Shopify could not settle gets the new term's link" do
    rental = with_checkout(create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago), old_id, :paid)
    fake.draft_statuses[old_id] = "COMPLETED"
    fake.on_query = ->(query, _) { raise Errno::ECONNRESET if query.include?("draftOrderDelete") }
    allow(Rails.error).to receive(:report)
    log_in!(owner)

    patch renew_locker_rental_path(rental)
    expect(rental.reload).to have_attributes(state: "await_payment", shopify_draft_order_id: old_id)

    expect(rental.checkout_link).to eq(new_url)
    expect(rental.checkout_state).to eq(:link)
    expect(rental.reload.shopify_draft_order_id).to eq(new_id)
    expect(checkouts(rental)).to eq([[old_id, "paid"], [new_id, "open"]])
  end

  it "staff sending a cancelled rental back to payment: last term's open draft is not served, even before Shopify removes it" do
    rental = with_checkout(create(:locker_rental, :await_payment, rented_by: owner), old_id, :open)
    rental.update_columns(state: "cancelled", cancelled_at: Time.current)
    served = :not_asked
    fake.on_query = lambda do |query, _|
      next unless query.include?("draftOrderDelete") && served == :not_asked

      served = nil
      served = LockerRental.find(rental.id).checkout_link # the commit is done, the sync has not finished
    end
    log_in!(staff)

    patch locker_rental_path(rental), params: { locker_rental: { state: "await_payment" } }
    expect(rental.reload.state).to eq("await_payment")

    expect(served).to eq(new_url)
    expect(rental.reload.shopify_draft_order_id).to eq(new_id)
    expect(checkouts(rental)).to eq([[old_id, "void"], [new_id, "open"]])
  end

  it "an unknown draft status is reported even when the cache cannot record the report" do
    failing = Class.new(ActiveSupport::Cache::MemoryStore) do
      def write_entry(*, **) = false
      def read_entry(*, **) = nil
    end
    allow(Rails).to receive(:cache).and_return(failing.new)
    rental = with_checkout(create(:locker_rental, :await_payment, rented_by: owner), old_id, :open)
    fake.draft_statuses[old_id] = "WEIRD"
    reports = []
    allow(Rails.error).to receive(:report) { |error, **| reports << error }

    expect(rental.checkout_link).to be_nil
    expect(rental.checkout_state).to eq(:unexpected_status)
    expect(rental.checkout_link).to be_nil
    expect(reports).to contain_exactly(be_a(LockerRental::UnknownDraftStatus), be_a(LockerRental::UnknownDraftStatus))
  end
end
