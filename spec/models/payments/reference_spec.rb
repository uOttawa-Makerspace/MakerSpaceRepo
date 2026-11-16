# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Reference do
  it "holds a known kind as a string, a record id and an Integer checkout id" do
    reference = described_class.new(kind: :locker, record_id: 3, checkout_id: 9)
    expect([reference.kind, reference.record_id, reference.checkout_id]).to eq(["locker", 3, 9])
    expect(described_class.new(kind: "membership").checkout_id).to be_nil
  end

  it "refuses a kind no checkout is made for" do
    expect { described_class.new(kind: "shop", record_id: 1) }.to raise_error(ArgumentError, /unknown reference kind/)
  end

  it "refuses a checkout id that is not an Integer, so it cannot carry search terms into a tag search" do
    expect { described_class.new(kind: "locker", checkout_id: "7 OR tag:x") }.to raise_error(ArgumentError, /Integer/)
    expect { described_class.new(kind: "locker", checkout_id: "7") }.to raise_error(ArgumentError, /Integer/)
  end
end
