# frozen_string_literal: true

require "rails_helper"

# Where a locker rental's pay link comes from when a rental starts a new term, when Shopify could not settle last
# term's draft, and when a draft has a status nobody expects.
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

  it "a renewal whose last-term draft Shopify could not settle gets the new term's link" do
    rental = with_checkout(create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago), old_id, :paid)
    fake.draft_statuses[old_id] = "COMPLETED"
    fake.on_query = ->(query, _) { raise Errno::ECONNRESET if query.include?("draftOrderDelete") }
    allow(Rails.error).to receive(:report)
    log_in!(owner)

    patch renew_locker_rental_path(rental)
    expect(rental.reload).to have_attributes(state: "await_payment", shopify_draft_order_id: old_id)

    expect(rental.checkout_link).to be_nil
    expect(rental.checkout_state).to eq(:processing)
  end

  it "staff sending a cancelled rental back to payment: last term's open draft is not served before Shopify removes it" do
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

    expect(served).to eq(old_url)
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
    expect(reports).to be_empty
  end
end
