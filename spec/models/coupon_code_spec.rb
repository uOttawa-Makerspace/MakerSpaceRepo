# frozen_string_literal: true

require "rails_helper"

RSpec.describe CouponCode, type: :model do
  let(:user) { create(:user, :regular_user) }

  it { should belong_to(:user).optional }

  it "refuses a negative price, accepts 0" do
    expect(CouponCode.new(cc_cost: -1, code: "A", dollar_cost: 5)).not_to be_valid
    expect(CouponCode.new(cc_cost: 0, code: "A", dollar_cost: 5)).to be_valid
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

  it "requires a price and a code" do
    expect(CouponCode.new(cc_cost: 0, code: "", dollar_cost: 5)).not_to be_valid
    expect(CouponCode.new(cc_cost: 0, code: nil, dollar_cost: 5)).not_to be_valid
    expect(CouponCode.new(cc_cost: 0, code: "ABC", dollar_cost: 5)).to be_valid
  end

  it "requires a positive dollar value" do
    [nil, 0, -5].each do |value|
      coupon = CouponCode.new(cc_cost: 10, code: "ABC", dollar_cost: value)
      expect(coupon).not_to be_valid, "for #{value.inspect}"
      expect(coupon.errors[:dollar_cost]).to be_present
    end
  end

  it "refuses a code another coupon already has" do
    create(:coupon_code, code: "SAVE5")
    duplicate = CouponCode.new(cc_cost: 10, code: "SAVE5", dollar_cost: 5)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:code]).to be_present
  end

  describe "an existing coupon that predates the rules" do
    let!(:legacy_a) { create(:coupon_code, :unclaimed, code: "DUP") }
    let!(:legacy_b) { create(:coupon_code, :claimed, user: user, code: "OTHER") }

    before do
      legacy_a.update_columns(code: "")
      legacy_b.update_columns(code: "", dollar_cost: nil)
    end

    it "can still be claimed, assigned or edited over an unrelated field" do
      expect(legacy_a.reload.update(cc_cost: 20)).to be(true)
      expect(legacy_b.reload.update(user: nil)).to be(true)
    end

    it "is checked again once its code or dollar value is edited" do
      expect(legacy_a.reload.update(code: "")).to be(true)
      expect(legacy_a.update(code: " ")).to be(false)
      expect(legacy_b.reload.update(dollar_cost: 0)).to be(false)
    end
  end

  it "refuses a blank, a non-numeric and a negative price with ONE message (a single numericality rule)" do
    message = ["must be a number of CCs (0 or more)"]
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

  it "stores integer amounts (a fractional price or dollar value is refused, never truncated)" do
    expect(CouponCode.new(cc_cost: 49.9, code: "A", dollar_cost: 7)).not_to be_valid
    expect(CouponCode.new(cc_cost: 49, code: "A", dollar_cost: 7.9)).not_to be_valid
    c = CouponCode.create!(dollar_cost: 7, cc_cost: 49, code: "A")
    expect([c.reload.dollar_cost, c.cc_cost]).to eq([7, 49])
  end

  it "can be destroyed while unclaimed" do
    coupon = create(:coupon_code, :unclaimed)
    expect { coupon.destroy }.to change(CouponCode, :count).by(-1)
  end

  it "cannot be destroyed once claimed" do
    coupon = create(:coupon_code, :claimed, user: user)
    expect(coupon.destroy).to be(false)
    expect(coupon.errors.full_messages).to eq(["A user has already claimed this coupon with CCs, so it cannot be deleted"])
    expect(CouponCode.exists?(coupon.id)).to be(true)
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
