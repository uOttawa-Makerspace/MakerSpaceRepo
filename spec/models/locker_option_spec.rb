# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockerOption, type: :model do
  describe ".locker_product_info" do
    let(:gid) { "gid://shopify/Product/1" }
    let(:product) do
      { "id" => gid, "title" => "Locker", "status" => "ACTIVE",
        "media" => { "nodes" => [] },
        "variants" => { "nodes" => [{ "id" => "v1", "displayName" => "Small", "title" => "S", "price" => "10.00",
                                      "sku" => "S1", "media" => { "nodes" => [] } }] } }
    end

    before { described_class.locker_product_link = gid }

    it "returns the product details with its variants" do
      allow(Payments::ShopifyCatalog).to receive(:product).with(gid).and_return(product)
      info = described_class.locker_product_info
      expect(info).to include(title: "Locker", id: gid)
      expect(info[:variants]["v1"]).to include(displayName: "Small", price: "10.00")
    end

    it "returns nil and reports once when Shopify raises" do
      allow(Payments::ShopifyCatalog).to receive(:product).and_raise(Faraday::ConnectionFailed, "down")
      expect(Rails.error).to receive(:report).once
        .with(instance_of(Faraday::ConnectionFailed), hash_including(handled: true, context: hash_including(source: "locker_option.locker_product_info")))
      expect(described_class.locker_product_info).to be_nil
    end

    it "returns nil and reports when Shopify has no such product" do
      allow(Payments::ShopifyCatalog).to receive(:product).and_return(nil)
      expect(Rails.error).to receive(:report).once
        .with(instance_of(LockerOption::LockerProductMissing), hash_including(handled: true))
      expect(described_class.locker_product_info).to be_nil
    end

    it "returns nil without calling Shopify when no link is stored" do
      described_class.find_by(name: described_class::LOCKER_PRODUCT_LINK).update_columns(value: nil)
      expect(Payments::ShopifyCatalog).not_to receive(:product)
      expect(described_class.locker_product_info).to be_nil
    end
  end
end
