# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Airbrake blocklist" do
  let(:keys) { Rails.application.config.x.airbrake_blocklist_keys }

  %w[password refresh_token access_token Authorization X-Refresh-Token HTTP_AUTHORIZATION token X-Shopify-Hmac-Sha256 HTTP_X_SHOPIFY_HMAC_SHA256].each do |name|
    it "filters #{name}" do
      expect(keys.any? { |re| re.match?(name) }).to be(true)
    end
  end

  it "does not filter ordinary params" do
    expect(keys.any? { |re| re.match?("username") }).to be(false)
  end

  it "filters the Shopify webhook signature header out of a notice's request headers" do
    notice = Airbrake::Notice.new(RuntimeError.new("boom"))
    notice[:context][:headers] = {
      "HTTP_X_SHOPIFY_HMAC_SHA256" => "c2lnbmF0dXJl",
      "HTTP_X_SHOPIFY_TOPIC" => "orders/paid"
    }

    Airbrake::Filters::KeysBlocklist.new(keys).call(notice)

    expect(notice[:context][:headers]).to eq(
      "HTTP_X_SHOPIFY_HMAC_SHA256" => "[Filtered]",
      "HTTP_X_SHOPIFY_TOPIC" => "orders/paid"
    )
  end
end
