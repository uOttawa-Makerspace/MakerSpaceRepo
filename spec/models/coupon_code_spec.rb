# frozen_string_literal: true

require "rails_helper"

RSpec.describe CouponCode, type: :model do
  let(:user) { create(:user, :regular_user) }

  it { should belong_to(:user).optional }

  it "refuses a negative price, accepts 0" do
    expect(CouponCode.new(cc_cost: -1)).not_to be_valid
    expect(CouponCode.new(cc_cost: 0)).to be_valid
  end

  it "the database refuses a negative or a NULL price too (CHECK coupon_codes_cc_cost_non_negative, NOT NULL)" do
    coupon = create(:coupon_code, :unclaimed, cc_cost: 10)
    expect do
      CouponCode.transaction(requires_new: true) { coupon.update_column(:cc_cost, -1) }
    end.to raise_error(ActiveRecord::CheckViolation, /coupon_codes_cc_cost_non_negative/)
    expect do
      CouponCode.transaction(requires_new: true) { coupon.update_column(:cc_cost, nil) }
    end.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "requires a price; a blank code is still accepted" do
    expect(CouponCode.new(cc_cost: 0, code: "")).to be_valid
  end

  it "refuses a blank, a non-numeric and a negative price with ONE message (a single numericality rule)" do
    message = ["must be a number of CC points (0 or more)"]
    [nil, "", "abc", -1, "2.9", 2.9].each do |price|
      expect(CouponCode.new(cc_cost: price).tap(&:valid?).errors[:cc_cost]).to eq(message), "for #{price.inspect}"
    end
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

  it "stores an integer price (a fractional price is refused, never truncated; dollar_cost still truncates)" do
    expect(CouponCode.new(cc_cost: 49.9)).not_to be_valid
    c = CouponCode.create!(dollar_cost: 7.9, cc_cost: 49)
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
        expect { CouponCode.claim!(user, 5, 40) }
          .to raise_error(ArgumentError, "claim! must run as its own transaction")
      end
      expect(coupon.reload.user_id).to be_nil
      expect(user.cc_moneys.where("cc < 0")).to be_empty
    end

    it "sets lock_timeout = 5s for its own transaction" do
      create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
      seen = nil
      allow(CcMoney).to receive(:debit_all!).and_wrap_original do |original, *args, **kw|
        seen = CouponCode.connection.select_value("SELECT current_setting('lock_timeout')")
        original.call(*args, **kw)
      end
      expect(CouponCode.claim!(user, 5, 40).first).to eq(:claimed)
      expect(seen).to eq("5s")
    end
  end
end
