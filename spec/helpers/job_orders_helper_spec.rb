# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobOrdersHelper, type: :helper do
  describe "#job_service_label" do
    let(:service) { build(:job_service, name: "PLA", unit: "g", internal_price: 10, external_price: 1234.5) }

    it "shows the internal price to an internal user" do
      user = build(:user)
      allow(user).to receive(:internal?).and_return(true)

      expect(helper.job_service_label(service, user)).to eq("PLA ($10.0/g)")
    end

    it "shows the external price to anyone else, without grouping the digits" do
      user = build(:user)
      allow(user).to receive(:internal?).and_return(false)

      expect(helper.job_service_label(service, user)).to eq("PLA ($1234.5/g)")
    end

    it "writes the price the French way in French" do
      user = build(:user)
      allow(user).to receive(:internal?).and_return(false)

      I18n.with_locale(:fr) { expect(helper.job_service_label(service, user)).to eq("PLA (1234,5 $/g)") }
    end
  end
end
