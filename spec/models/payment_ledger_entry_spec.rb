# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentLedgerEntry do
  def entry(**attrs)
    described_class.new(provider: "shopify", provider_ref: "1001", amount: "25.00", kind: "payment", **attrs)
  end

  let(:payment) { entry.tap(&:save!) }

  it "saves a payment, and a reversal pointing at it with the same provider ref" do
    reversal = entry(kind: "reversal", reversed_entry: payment)

    expect(reversal.save).to be(true)
    expect(reversal.reload.reversed_entry).to eq(payment)
  end

  it "needs a provider, a provider ref and a known kind, and no negative amount" do
    record = described_class.new(kind: "refund", amount: "-1")

    expect(record).not_to be_valid
    expect(record.errors.attribute_names).to include(:provider, :provider_ref, :kind, :amount)
    expect(entry(amount: nil)).to be_valid
  end

  it "allows one payment per provider ref" do
    payment

    expect(entry).not_to be_valid
    expect(entry(provider: "other")).to be_valid
  end

  it "gives a reversal exactly one payment, and a payment none" do
    expect(entry(kind: "reversal")).not_to be_valid
    expect(entry(provider_ref: "1002", reversed_entry: payment)).not_to be_valid

    entry(kind: "reversal", reversed_entry: payment).save!
    expect(entry(kind: "reversal", reversed_entry: payment)).not_to be_valid
  end

  it "cannot change or remove a saved entry" do
    expect { payment.update!(amount: "1.00") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { payment.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "is refused by the database when changed or removed around the model" do
    id = payment.id

    expect { described_class.transaction(requires_new: true) { described_class.where(id: id).update_all(amount: 0) } }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only: UPDATE refused/)
    expect { described_class.transaction(requires_new: true) { described_class.where(id: id).delete_all } }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only: DELETE refused/)
    expect(described_class.find(id).amount).to eq(BigDecimal("25.00"))
  end
end
