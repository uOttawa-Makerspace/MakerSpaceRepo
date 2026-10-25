# frozen_string_literal: true

require "rails_helper"

# Wallet = users.wallet, a cached integer refreshed by User#update_wallet.
RSpec.describe User, "wallet", type: :model do
  let(:user) { create(:user, :regular_user) }

  it "has a column default of 0 (the factory seeds 1000)" do
    expect(User.columns_hash["wallet"].default).to eq(0)
  end

  it "#update_wallet overwrites the cache with the cc_moneys sum (positive and negative rows)" do
    CcMoney.create!(user: user, cc: 70)
    CcMoney.create!(user: user, cc: -20)
    expect(user.update_wallet).to be(true)
    expect(user.reload.wallet).to eq(50)
  end

  it "becomes 0 when the user has no cc_moneys at all" do
    user.update_wallet
    expect(user.reload.wallet).to eq(0)
  end

  it "does not persist for an unsaved (guest) user" do
    expect(User.new.update_wallet).to be(false)
  end
end
