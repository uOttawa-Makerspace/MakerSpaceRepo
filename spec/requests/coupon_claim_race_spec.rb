# frozen_string_literal: true

require "rails_helper"

# D-S33: DiscountCodesController#create is find unclaimed -> charge wallet -> assign,
# with no lock and no atomic "claim if still unclaimed". This pins today's behavior
# for two claims of the same dollar_cost coupon that interleave.
#
# The interleaving is made deterministic without threads: user A's request has
# already loaded the coupon (before_action) when it reaches CcMoney.make_new_payment;
# at that exact point user B's whole request runs to completion in a second
# integration session, then A's request continues with its stale coupon.
RSpec.describe "Coupon claim race (D-S33)", type: :request do
  let(:password) { "asa32A353#" }
  let(:user_a) { create(:user, :regular_user) }
  let(:user_b) { create(:user, :regular_user) }
  let!(:coupon) { create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40) }

  before do
    credit_cc!(user_a, 100)
    credit_cc!(user_b, 100)
  end

  def login_session(user)
    open_session.tap do |s|
      s.post login_authentication_path, params: { username_email: user.username, password: password }
      expect(s.response.location).to end_with(root_path)
    end
  end

  # Runs `outer` request; while it is between loading the coupon and assigning it,
  # `inner_session` completes its own claim of the same coupon.
  def interleave(outer_session, inner_session)
    inner_response = nil
    nested = false
    allow(CcMoney).to receive(:make_new_payment).and_wrap_original do |original, *args|
      unless nested
        nested = true
        inner_session.post discount_codes_path, params: { dollar_cost: 5 }
        inner_response = inner_session.response
      end
      original.call(*args)
    end
    outer_session.post discount_codes_path, params: { dollar_cost: 5 }
    inner_response
  end

  it "charges BOTH users for one coupon: the stale request overwrites the first claimant (the loser keeps a debit and no coupon)" do
    # WART(D-S33): no lock / atomic claim. B completes a full claim (debited 40, coupon.user = B),
    # then A, holding a stale unclaimed coupon, is debited 40 too and its update overwrites
    # user_id to A. Result: two debits, one coupon, owner = the LAST writer (A); B paid and has nothing.
    session_a = login_session(user_a)
    session_b = login_session(user_b)

    b_response = interleave(session_a, session_b)

    # both requests report success
    expect(b_response.location).to end_with(discount_codes_path)
    expect(session_a.response.location).to end_with(discount_codes_path)
    expect(session_a.flash[:notice]).to eq("Discount Code created")
    expect(session_b.flash[:notice]).to eq("Discount Code created")

    # one coupon, owned by the last writer
    expect(coupon.reload.user_id).to eq(user_a.id)
    expect(CouponCode.where(dollar_cost: 5).count).to eq(1)
    expect(CouponCode.unclaimed.count).to eq(0)

    # both wallets were charged 40
    expect(user_a.cc_moneys.where("cc < 0").pluck(:cc)).to eq([-40])
    expect(user_b.cc_moneys.where("cc < 0").pluck(:cc)).to eq([-40])
    expect(user_a.reload.wallet).to eq(60)
    expect(user_b.reload.wallet).to eq(60)

    # user B paid for a coupon they do not own
    expect(CouponCode.where(user_id: user_b.id)).to be_empty
    expect(CouponCode.where(user_id: user_a.id).pluck(:id)).to eq([coupon.id])
  end

  it "without interleaving the same two claims behave: the second user finds no coupon (D-S09 500) and is not charged" do
    session_a = login_session(user_a)
    session_b = login_session(user_b)

    session_a.post discount_codes_path, params: { dollar_cost: 5 }
    expect(session_a.response.location).to end_with(discount_codes_path)
    expect(coupon.reload.user_id).to eq(user_a.id)

    session_b.post discount_codes_path, params: { dollar_cost: 5 }
    # WART(D-S09): the missing-coupon filter redirects then dereferences nil, so a 500
    expect(session_b.response.status).to eq(500)
    expect(user_b.cc_moneys.where("cc < 0")).to be_empty
    expect(user_b.reload.wallet).to eq(100)
    expect(user_a.reload.wallet).to eq(60)
  end
end
