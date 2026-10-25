# frozen_string_literal: true

require "rails_helper"

RSpec.describe CouponCode, type: :model do
  let(:user) { create(:user, :regular_user) }

  it { should belong_to(:user).optional }

  it "has no validations (blank code and prices are accepted)" do
    expect(CouponCode.new).to be_valid
    expect { CouponCode.create! }.not_to raise_error
  end

  it "scopes unclaimed/claimed by user_id" do
    free = create(:coupon_code, :unclaimed)
    taken = create(:coupon_code, :claimed, user: user)
    expect(CouponCode.unclaimed).to contain_exactly(free)
    expect(CouponCode.claimed).to contain_exactly(taken)
  end

  it "#title renders the dollar value" do
    expect(CouponCode.new(dollar_cost: 15).title).to eq("$15 off MakerStore")
    expect(CouponCode.new.title).to eq("$ off MakerStore")
  end

  it "stores integer dollar/cc costs (decimal input is truncated)" do
    c = CouponCode.create!(dollar_cost: 7.9, cc_cost: 49.9)
    expect([c.reload.dollar_cost, c.cc_cost]).to eq([7, 49])
  end

  it "is destroyed with its user" do
    create(:coupon_code, :claimed, user: user)
    expect { user.destroy }.to change(CouponCode, :count).by(-1)
  end
end
