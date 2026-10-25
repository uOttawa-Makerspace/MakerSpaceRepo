# frozen_string_literal: true

require "rails_helper"

# Characterization of the cc-points economy outside checkout:
# * CouponCode claims through DiscountCodesController (cc points -> coupon),
# * CouponCodesController (admin CRUD),
# * PriceRulesController (admin CRUD, Shopify REST stubbed at the model seam),
# * CcMoneysController (wallet page, link/redeem a mailed cc token).
# Auth is the custom session driven by a real login POST. No external HTTP.
RSpec.describe "Shop coupons, price rules and cc money (HTTP contract)", type: :request do
  let(:user) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  # =================================================== discount codes (claim)

  describe "DiscountCodesController" do
    describe "auth gates" do
      it "redirects guests to login on index/new/create" do
        get discount_codes_path
        expect(response).to redirect_to(login_path(back_to: "/discount_codes"))
        get new_discount_code_path
        expect(response).to redirect_to(login_path(back_to: "/discount_codes/new"))
        post discount_codes_path, params: { dollar_cost: 5 }
        expect(response).to redirect_to(login_path(back_to: "/discount_codes"))
        expect(CouponCode.count).to eq(0)
      end
    end

    describe "GET /discount_codes" do
      it "lists only the coupons the user has claimed" do
        create(:coupon_code, :claimed, user: user, code: "MINE-123", dollar_cost: 5)
        create(:coupon_code, :claimed, user: other, code: "THEIRS-456", dollar_cost: 10)
        create(:coupon_code, :unclaimed, code: "FREE-789", dollar_cost: 15)
        shop_log_in!(user)
        get discount_codes_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("MINE-123")
        expect(response.body).not_to include("THEIRS-456")
        expect(response.body).not_to include("FREE-789")
      end

      it "shows the empty state when the user has none" do
        shop_log_in!(user)
        get discount_codes_path
        expect(response.body).to include("You don't have any coupons.")
      end

      it "gives staff and admin the same own-codes-only view" do
        create(:coupon_code, :claimed, user: other, code: "THEIRS-456")
        [staff, admin].each do |u|
          get logout_path
          shop_log_in!(u)
          get discount_codes_path
          expect(response).to have_http_status(:ok)
          expect(response.body).not_to include("THEIRS-456")
        end
      end
    end

    describe "GET /discount_codes/new" do
      it "offers one card per distinct unclaimed (dollar, cc) pair; claimed ones are hidden" do
        create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 50)
        create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 50)
        create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 90)
        create(:coupon_code, :claimed, user: other, dollar_cost: 99, cc_cost: 1)
        shop_log_in!(user)
        get new_discount_code_path
        expect(response).to have_http_status(:ok)
        expect(response.body.scan("Are you sure you want to buy the coupon").size).to eq(2)
        expect(response.body).to include("$5 off our MakerStore")
        expect(response.body).to include("$10 off our MakerStore")
        expect(response.body).not_to include("$99 off")
      end

      it "shows the sold-out message when nothing is unclaimed" do
        shop_log_in!(user)
        get new_discount_code_path
        expect(response.body).to include("we don't have any coupons to offer")
      end
    end

    describe "POST /discount_codes" do
      before { shop_log_in!(user) }

      it "spends cc points, claims the first unclaimed coupon of that dollar value" do
        credit_cc!(user, 100)
        first = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)

        expect { post discount_codes_path, params: { dollar_cost: 5 } }
          .to change(CcMoney, :count).by(1)

        expect(response).to redirect_to(discount_codes_path)
        expect(flash[:notice]).to eq("Discount Code created")
        expect(first.reload.user_id).to eq(user.id)
        expect(CouponCode.unclaimed.count).to eq(1)
        payment = user.cc_moneys.order(:id).last
        expect(payment.cc).to eq(-40)
        expect(payment.order_id).to be_nil
        expect(user.reload.wallet).to eq(60)
      end

      it "allows an exact-balance purchase" do
        credit_cc!(user, 40)
        create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        post discount_codes_path, params: { dollar_cost: 5 }
        expect(flash[:notice]).to eq("Discount Code created")
        expect(user.reload.wallet).to eq(0)
      end

      it "rejects with an alert when the wallet is short; nothing changes" do
        credit_cc!(user, 39)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        expect { post discount_codes_path, params: { dollar_cost: 5 } }.not_to change(CcMoney, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Not enough CC points")
        expect(coupon.reload.user_id).to be_nil
      end

      it "does not touch coupons already claimed by someone else (same dollar value)" do
        credit_cc!(user, 100)
        taken = create(:coupon_code, :claimed, user: other, dollar_cost: 5, cc_cost: 10)
        expect { post discount_codes_path, params: { dollar_cost: 5 } }.not_to change(CcMoney, :count)
        # same nil-dereference crash as an unknown value (D-S09)
        expect(response).to have_http_status(:internal_server_error)
        expect(taken.reload.user_id).to eq(other.id)
      end

      it "answers with the 'Can not find coupon' alert flash and then 500s on the unknown dollar value" do
        credit_cc!(user, 100)
        # WART(D-S09): after redirecting for a missing coupon the filter keeps going and dereferences nil (@price_rule.user), so the user sees a 500 instead of the redirect
        expect { post discount_codes_path, params: { dollar_cost: 777 } }.not_to change(CcMoney, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "is available to staff and admin with the same economics" do
        [staff, admin].each do |u|
          get logout_path
          shop_log_in!(u)
          credit_cc!(u, 50)
          coupon = create(:coupon_code, :unclaimed, dollar_cost: 7, cc_cost: 20)
          post discount_codes_path, params: { dollar_cost: 7 }
          expect(flash[:notice]).to eq("Discount Code created")
          expect(coupon.reload.user_id).to eq(u.id)
          expect(u.reload.wallet).to eq(30)
        end
      end
    end
  end

  # ============================================== coupon codes (admin CRUD)

  describe "CouponCodesController" do
    let!(:coupon) { create(:coupon_code, :unclaimed, code: "ABC", dollar_cost: 5, cc_cost: 50) }

    it "redirects guests to login on every action" do
      get coupon_codes_path
      expect(response).to redirect_to(login_path(back_to: "/coupon_codes"))
      post coupon_codes_path, params: { coupon_code: { code: "X", cc_cost: 1, dollar_cost: 1 } }
      expect(response).to redirect_to(login_path(back_to: "/coupon_codes"))
      delete coupon_code_path(coupon)
      expect(response).to redirect_to(login_path(back_to: "/coupon_codes/#{coupon.id}"))
      expect(CouponCode.exists?(coupon.id)).to be(true)
    end

    it "bounces non-admins (user, staff) to root with 'Admin access only.' and changes nothing" do
      [user, staff].each do |u|
        get logout_path
        shop_log_in!(u)

        get coupon_codes_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Admin access only.")

        get edit_coupon_code_path(coupon)
        expect(response).to redirect_to(root_path)

        expect { post coupon_codes_path, params: { coupon_code: { code: "X", cc_cost: 1, dollar_cost: 1 } } }
          .not_to change(CouponCode, :count)
        expect(response).to redirect_to(root_path)

        patch coupon_code_path(coupon), params: { coupon_code: { code: "HACK" } }
        expect(response).to redirect_to(root_path)
        expect(coupon.reload.code).to eq("ABC")

        expect { delete coupon_code_path(coupon) }.not_to change(CouponCode, :count)
        expect(response).to redirect_to(root_path)
      end
    end

    context "as admin" do
      before { shop_log_in!(admin) }

      it "lists unclaimed and claimed coupons separately" do
        create(:coupon_code, :claimed, user: other, code: "CLAIMED-1")
        get coupon_codes_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ABC")
        expect(response.body).to include("CLAIMED-1")
      end

      it "creates a coupon" do
        expect do
          post coupon_codes_path, params: { coupon_code: { code: "NEW-1", cc_cost: 25, dollar_cost: 3 } }
        end.to change(CouponCode, :count).by(1)
        expect(response).to redirect_to(coupon_codes_path)
        expect(flash[:notice]).to eq("Coupon code was successfully created.")
        created = CouponCode.find_by!(code: "NEW-1")
        expect(created.cc_cost).to eq(25)
        expect(created.dollar_cost).to eq(3)
        expect(created.user_id).to be_nil
      end

      it "ignores user_id in mass assignment (not permitted)" do
        post coupon_codes_path, params: { coupon_code: { code: "NEW-2", cc_cost: 1, dollar_cost: 1, user_id: other.id } }
        expect(CouponCode.find_by!(code: "NEW-2").user_id).to be_nil
      end

      it "accepts a coupon with no code/prices at all" do
        # WART(D-S10): CouponCode has no validations, so a blank, free coupon can be created
        expect { post coupon_codes_path, params: { coupon_code: { code: "" } } }.to change(CouponCode, :count).by(1)
        expect(CouponCode.last.code).to eq("")
        expect(CouponCode.last.cc_cost).to be_nil
      end

      it "renders the edit page" do
        get edit_coupon_code_path(coupon)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ABC")
      end

      it "updates a coupon" do
        patch coupon_code_path(coupon), params: { coupon_code: { code: "ABC2", cc_cost: 60, dollar_cost: 6 } }
        expect(response).to redirect_to(coupon_codes_path)
        expect(flash[:notice]).to eq("Coupon code was successfully updated.")
        expect(coupon.reload.attributes.slice("code", "cc_cost", "dollar_cost"))
          .to eq({ "code" => "ABC2", "cc_cost" => 60, "dollar_cost" => 6 })
      end

      it "deletes a coupon, even one a user already paid for" do
        claimed = create(:coupon_code, :claimed, user: other)
        # WART(D-S11): deleting a claimed coupon silently destroys what the user spent cc on, with no refund
        expect { delete coupon_code_path(claimed) }.to change(CouponCode, :count).by(-1)
        expect(response).to redirect_to(coupon_codes_path)
        expect(flash[:notice]).to eq("Coupon code was successfully deleted.")
      end

      it "404s for an unknown id" do
        get edit_coupon_code_path(999_999_999)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ================================================ price rules (admin CRUD)

  describe "PriceRulesController" do
    let!(:rule) { create(:price_rule, title: "5$ coupon", value: 5, cc: 50, shopify_price_rule_id: "111") }
    let(:valid_params) { { price_rule: { title: "10$ coupon", value: 10, cc: 90 } } }

    it "redirects guests to login on every action" do
      get price_rules_path
      expect(response).to redirect_to(login_path(back_to: "/price_rules"))
      post price_rules_path, params: valid_params
      expect(response).to redirect_to(login_path(back_to: "/price_rules"))
      expect(PriceRule.count).to eq(1)
    end

    it "bounces regular users and staff to root with 'Forbbiden Area'" do
      expect(PriceRule).not_to receive(:create_price_rule)
      expect(PriceRule).not_to receive(:delete_price_rule_from_shopify)
      [user, staff].each do |u|
        get logout_path
        shop_log_in!(u)
        get price_rules_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Forbbiden Area")
        post price_rules_path, params: valid_params
        expect(response).to redirect_to(root_path)
        delete price_rule_path(rule)
        expect(response).to redirect_to(root_path)
      end
      expect(PriceRule.count).to eq(1)
    end

    context "as admin" do
      before { shop_log_in!(admin) }

      it "lists and renders new/edit" do
        get price_rules_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("5$ coupon")
        get new_price_rule_path
        expect(response).to have_http_status(:ok)
        get edit_price_rule_path(rule)
        expect(response).to have_http_status(:ok)
      end

      it "create: registers the rule at Shopify first, stores the returned id" do
        expect(PriceRule).to receive(:create_price_rule).with("10$ coupon", 10).and_return(987_654)
        expect { post price_rules_path, params: valid_params }.to change(PriceRule, :count).by(1)
        expect(response).to redirect_to(price_rules_path)
        expect(flash[:notice]).to eq("Price rule was successfully created.")
        created = PriceRule.last
        expect(created.shopify_price_rule_id).to eq("987654")
        expect([created.title, created.value, created.cc]).to eq(["10$ coupon", 10, 90])
      end

      it "create: json responds 201 (renders index) and 422 + errors when Shopify gives no id" do
        allow(PriceRule).to receive(:create_price_rule).and_return(1)
        post price_rules_path, params: valid_params, as: :json
        expect(response).to have_http_status(:created)

        allow(PriceRule).to receive(:create_price_rule).and_return(nil)
        post price_rules_path, params: valid_params, as: :json
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)).to eq("shopify_price_rule_id" => ["This field is required."])
      end

      it "create: html re-renders the form with 200 when invalid, after already calling Shopify" do
        # WART(D-S12): the Shopify rule is created BEFORE local validation, so invalid input (blank cc) orphans a live Shopify price rule
        expect(PriceRule).to receive(:create_price_rule).with("Bad", 5).and_return(42)
        expect do
          post price_rules_path, params: { price_rule: { title: "Bad", value: 5, cc: "" } }
        end.not_to change(PriceRule, :count)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("cc")
      end

      it "update: saves locally then pushes title/value to Shopify" do
        expect(PriceRule).to receive(:update_price_rule).with("111", "New title", 7)
        patch price_rule_path(rule), params: { price_rule: { title: "New title", value: 7, cc: 70 } }
        expect(response).to redirect_to(price_rules_url)
        expect(flash[:notice]).to eq("Price rule was successfully updated.")
        expect([rule.reload.title, rule.value, rule.cc]).to eq(["New title", 7, 70])
      end

      it "update: invalid input re-renders edit and does not call Shopify" do
        expect(PriceRule).not_to receive(:update_price_rule)
        patch price_rule_path(rule), params: { price_rule: { title: "" } }
        expect(response).to have_http_status(:ok)
        expect(rule.reload.title).to eq("5$ coupon")
      end

      it "edit/update refuse a rule that already has discount codes; destroy does NOT" do
        create(:discount_code, price_rule: rule, user: other)
        expect(PriceRule).not_to receive(:update_price_rule)
        get edit_price_rule_path(rule)
        expect(response).to redirect_to(price_rules_path)
        expect(flash[:alert]).to eq("This price rule cannot be edited/deleted because it has already discount codes")
        patch price_rule_path(rule), params: { price_rule: { title: "X" } }
        expect(response).to redirect_to(price_rules_path)
        expect(rule.reload.title).to eq("5$ coupon")

        # WART(D-S13): the guard message says "edited/deleted" but destroy is not guarded, it deletes the rule and cascades its discount codes
        expect(PriceRule).to receive(:delete_price_rule_from_shopify).with("111")
        expect { delete price_rule_path(rule) }
          .to change(PriceRule, :count).by(-1).and change(DiscountCode, :count).by(-1)
        expect(response).to redirect_to(price_rules_url)
        expect(flash[:notice]).to eq("Price rule was successfully destroyed.")
      end

      it "destroy: deletes at Shopify and locally; json gives 204" do
        expect(PriceRule).to receive(:delete_price_rule_from_shopify).with("111")
        delete price_rule_path(rule), as: :json
        expect(response).to have_http_status(:no_content)
        expect(PriceRule.exists?(rule.id)).to be(false)
      end

      it "without the model stubs every Shopify-backed write is a 500 and nothing is persisted" do
        # see D-S32: the Shopify REST resources are never loaded, so this admin screen cannot work
        expect { post price_rules_path, params: valid_params }.not_to change(PriceRule, :count)
        expect(response).to have_http_status(:internal_server_error)

        patch price_rule_path(rule), params: { price_rule: { title: "Changed" } }
        expect(response).to have_http_status(:internal_server_error)

        expect { delete price_rule_path(rule) }.not_to change(PriceRule, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "has no show route (the show views are orphaned)" do
        get "/price_rules/#{rule.id}"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ============================================================= cc moneys

  describe "CcMoneysController" do
    let(:verifier) { Rails.application.message_verifier(:cc) }
    let!(:unlinked) { CcMoney.create!(cc: 20, linked: false) }
    let(:token) { verifier.generate(unlinked.id) }

    describe "GET /cc_moneys" do
      it "is public: guests see the explainer plus a zero balance card" do
        get cc_moneys_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("What Are CC Points?")
        # WART(D-S17): current_user is a blank User.new for guests, so the wallet card renders "0 CCs" and a Redeem button for visitors who are not signed in
        expect(response.body).to include("Your CC Balance")
        expect(response.body).to match(/0\s*<small/)
      end

      it "shows signed-in users their refreshed wallet and last 10 activities" do
        CcMoney.create!(user: user, cc: 30)
        user.update_column(:wallet, 0)
        shop_log_in!(user)
        get cc_moneys_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Your CC Balance")
        expect(user.reload.wallet).to eq(30)
        expect(response.body).to match(/30\s*<small/)
      end

      it "caps the activity list at 10" do
        12.times { |i| CcMoney.create!(user: user, cc: i + 1) }
        shop_log_in!(user)
        get cc_moneys_path
        expect(response).to have_http_status(:ok)
        expect(user.cc_moneys.count).to eq(12)
      end
    end

    describe "GET /cc_moneys/link_cc_to_user" do
      it "redirects guests to login with the token preserved in back_to" do
        get link_cc_to_user_cc_moneys_path, params: { token: token }
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/login")
      end

      it "renders the email form for a valid, unlinked token" do
        shop_log_in!(user)
        get link_cc_to_user_cc_moneys_path, params: { token: token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Link CC to an user")
        expect(response.body).to include(token)
      end

      it "redirects with the 'already added' alert when the token was used" do
        unlinked.update!(linked: true)
        shop_log_in!(user)
        get link_cc_to_user_cc_moneys_path, params: { token: token }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
      end

      it "redirects with the generic alert for a tampered or missing token" do
        shop_log_in!(user)
        get link_cc_to_user_cc_moneys_path, params: { token: "garbage" }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to start_with("Something went wrong.")
        get link_cc_to_user_cc_moneys_path
        expect(response).to redirect_to(cc_moneys_path)
      end

      it "500s for a validly signed token whose cc_money row no longer exists" do
        stale = verifier.generate(999_999_999)
        shop_log_in!(user)
        get link_cc_to_user_cc_moneys_path, params: { token: stale }
        # WART(D-S14): no nil guard on CcMoney.find_by_id; a deleted row is a NoMethodError 500
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    describe "GET /cc_moneys/redeem" do
      it "redirects guests to login and changes nothing" do
        get redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        expect(response.location).to include("/login")
        expect(unlinked.reload.linked).to be(false)
      end

      it "links the points to the user whose email is submitted" do
        shop_log_in!(user)
        get redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:notice]).to eq("The CC Money has been added to #{user.name}")
        expect(unlinked.reload.user_id).to eq(user.id)
        expect(unlinked.linked).to be(true)
        expect(user.cc_moneys.sum(:cc)).to eq(20)
      end

      it "lets a signed-in user credit the points to ANY account by typing its email" do
        shop_log_in!(user)
        get redeem_cc_moneys_path, params: { token: token, user: { email: other.email } }
        # WART(D-S15): redeem trusts the submitted email, not the signed-in user, and does so on a GET (CSRF-able); anyone holding a mailed token can push the points to a third party
        expect(flash[:notice]).to eq("The CC Money has been added to #{other.name}")
        expect(unlinked.reload.user_id).to eq(other.id)
      end

      it "is single-use: a second redeem alerts and keeps the first owner" do
        shop_log_in!(user)
        get redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        get redeem_cc_moneys_path, params: { token: token, user: { email: other.email } }
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
        expect(unlinked.reload.user_id).to eq(user.id)
      end

      it "unknown email: misleading 'already added' alert, points stay unlinked" do
        shop_log_in!(user)
        get redeem_cc_moneys_path, params: { token: token, user: { email: "nobody@example.com" } }
        expect(response).to redirect_to(cc_moneys_path)
        # WART(D-S16): an unknown email reports "already added to an account" although nothing was linked
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
        expect(unlinked.reload.linked).to be(false)
      end

      it "tampered token raises InvalidSignature (500) and missing user param is a 302 to root" do
        shop_log_in!(user)
        get redeem_cc_moneys_path, params: { token: "bad", user: { email: user.email } }
        expect(response).to have_http_status(:internal_server_error)
        get redeem_cc_moneys_path, params: { token: token }
        expect(response).to redirect_to(root_path)
        expect(unlinked.reload.linked).to be(false)
      end
    end
  end
end
