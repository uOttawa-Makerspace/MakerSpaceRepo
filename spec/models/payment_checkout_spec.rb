# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentCheckout do
  let(:rental) { create(:locker_rental, :await_payment) }

  def checkout(**attrs)
    described_class.new(reference: rental, provider: "shopify", provider_id: "gid://shopify/DraftOrder/1", **attrs)
  end

  it "starts open and saves with its reference, provider and provider id" do
    record = checkout(term: Date.new(2026, 12, 31))

    expect(record.save).to be(true)
    expect(record.reload).to have_attributes(status: "open", reference: rental, term: Date.new(2026, 12, 31))
  end

  it "needs a reference, a provider and a known status" do
    record = described_class.new(status: "gone")

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to include(:reference, :provider, :status)
  end

  it "needs a provider id only once paid (a claim has none yet)" do
    claim = checkout(provider_id: nil)
    expect(claim).to be_valid
    claim.status = "paid"
    expect(claim).not_to be_valid
    expect(claim.errors.attribute_names).to eq([:provider_id])
  end

  it "allows one row per provider id" do
    checkout(status: "paid").save!

    expect(checkout(reference: create(:locker_rental, :await_payment))).not_to be_valid
  end

  it "allows one open checkout per reference, next to any number of paid or void ones" do
    checkout(status: "paid").save!
    checkout(provider_id: "gid://shopify/DraftOrder/2", status: "void").save!
    checkout(provider_id: "gid://shopify/DraftOrder/3").save!

    expect(checkout(provider_id: "gid://shopify/DraftOrder/4")).not_to be_valid
    expect(checkout(provider_id: "gid://shopify/DraftOrder/4", status: "void")).to be_valid
  end

  it "refuses a second open checkout in the database too" do
    checkout.save!
    second = checkout(provider_id: "gid://shopify/DraftOrder/2")

    expect { second.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
