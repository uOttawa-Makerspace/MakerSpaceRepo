# frozen_string_literal: true

# Shared setup for the locker page-script specs (spec/system/js/lockers): lockers
# switched on and the Shopify product lookup stubbed at the boundary, with one
# variant per size so the size selects have something to show.
RSpec.shared_context "with lockers on" do
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let!(:size_small) { create(:locker_size, size: "12x12", shopify_gid: "gid-small") }
  let!(:size_large) { create(:locker_size, size: "24x24", shopify_gid: "gid-large") }
  let(:variants) do
    {
      "gid-small" => { id: "gid-small", title: "Small variant", displayName: "Small locker", sku: "SKU-S", price: "10.00" },
      "gid-large" => { id: "gid-large", title: "Large variant", displayName: "Large locker", sku: "SKU-L", price: "20.00" },
      "gid-new" => { id: "gid-new", title: "New variant", displayName: "New locker", sku: "SKU-N", price: "30.00" }
    }
  end

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    LockerOption.lockers_enabled = true
    allow(LockerOption).to receive(:locker_product_info).and_return({ title: "Lockers", variants: variants })
    ActionMailer::Base.deliveries.clear
  end
end
