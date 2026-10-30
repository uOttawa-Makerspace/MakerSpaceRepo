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

  describe ".claim! transaction boundary" do
    before { credit_cc!(user, 100) }

    it "refuses to run inside an already-open transaction (it must be its own: no inherited lock_timeout)" do
      coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
      ActiveRecord::Base.transaction do
        expect { CouponCode.claim!(user, 5) }
          .to raise_error(ArgumentError, "claim! must run as its own transaction")
      end
      expect(coupon.reload.user_id).to be_nil
      expect(user.cc_moneys.where("cc < 0")).to be_empty
    end

    it "sets lock_timeout = 5s for its own transaction" do
      create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
      seen = nil
      allow(CcMoney).to receive(:make_new_payment).and_wrap_original do |original, *args|
        seen = CouponCode.connection.select_value("SELECT current_setting('lock_timeout')")
        original.call(*args)
      end
      expect(CouponCode.claim!(user, 5).first).to eq(:claimed)
      expect(seen).to eq("5s")
    end
  end
end
