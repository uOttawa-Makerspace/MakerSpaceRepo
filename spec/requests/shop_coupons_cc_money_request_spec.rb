# frozen_string_literal: true

require "rails_helper"

# Characterization of the cc-points economy outside checkout:
# * CouponCode claims through DiscountCodesController (cc points -> coupon),
# * CouponCodesController (admin CRUD),
# * CcMoneysController (wallet page, link/redeem a mailed cc token).
# Auth is the custom session driven by a real login POST. No external HTTP.
RSpec.describe "Shop coupons and cc money (HTTP contract)", type: :request do
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
        expect(response).to redirect_to(login_path)
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

        expect { post discount_codes_path, params: { dollar_cost: 5, cc_cost: 40 } }
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
        post discount_codes_path, params: { dollar_cost: 5, cc_cost: 40 }
        expect(flash[:notice]).to eq("Discount Code created")
        expect(user.reload.wallet).to eq(0)
      end

      it "rejects with an alert when the wallet is short; nothing changes" do
        credit_cc!(user, 39)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        expect { post discount_codes_path, params: { dollar_cost: 5, cc_cost: 40 } }.not_to change(CcMoney, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Not enough CC points")
        expect(coupon.reload.user_id).to be_nil
      end

      it "does not touch coupons already claimed by someone else (same dollar value)" do
        credit_cc!(user, 100)
        taken = create(:coupon_code, :claimed, user: other, dollar_cost: 5, cc_cost: 10)
        expect { post discount_codes_path, params: { dollar_cost: 5, cc_cost: 10 } }.not_to change(CcMoney, :count)
        # Fixed (was WART D-S09, a 500): redirect back to the offers with the alert
        expect(response).to redirect_to(new_discount_code_path)
        expect(flash[:alert]).to eq("Can not find coupon for $5 off")
        expect(taken.reload.user_id).to eq(other.id)
      end

      it "answers the 'Can not find coupon' alert and redirects to the offers on an unknown dollar value" do
        credit_cc!(user, 100)
        # Fixed (was WART D-S09): the filter now returns after its redirect instead of dereferencing nil (a 500)
        expect { post discount_codes_path, params: { dollar_cost: 777, cc_cost: 40 } }.not_to change(CcMoney, :count)
        expect(response).to redirect_to(new_discount_code_path)
        expect(flash[:alert]).to eq("Can not find coupon for $777 off")
      end

      it "a claim whose save fails changes nothing and answers the 'not created properly' alert (no 500)" do
        credit_cc!(user, 100)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        allow_any_instance_of(CouponCode).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(coupon))
        expect { post discount_codes_path, params: { dollar_cost: 5, cc_cost: 40 } }.not_to change(CcMoney, :count)
        expect(response).to redirect_to(discount_codes_path)
        expect(flash[:alert]).to eq("Discount Code not created properly!")
        expect(coupon.reload.user_id).to be_nil
        expect(user.reload.wallet).to eq(100)
      end

      it "a debit that is not saved changes nothing and answers the same alert" do
        credit_cc!(user, 100)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
        allow(CcMoney).to receive(:create!).and_raise(ActiveRecord::RecordNotSaved, "simulated")
        post discount_codes_path, params: { dollar_cost: 5, cc_cost: 40 }
        expect(response).to redirect_to(discount_codes_path)
        expect(flash[:alert]).to eq("Discount Code not created properly!")
        expect(coupon.reload.user_id).to be_nil
        expect(user.cc_moneys.where("cc < 0")).to be_empty
      end

      it "charges the price the user confirmed: two $10 coupons at 500 and 1000 CC, picking 500 charges 500" do
        credit_cc!(user, 2000)
        pricey = create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 1000) # lower id
        cheap = create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 500)
        post discount_codes_path, params: { dollar_cost: 10, cc_cost: 500 }
        expect(flash[:notice]).to eq("Discount Code created")
        expect(cheap.reload.user_id).to eq(user.id)
        expect(pricey.reload.user_id).to be_nil
        expect(user.cc_moneys.where("cc < 0").pluck(:cc)).to eq([-500])
        expect(user.reload.wallet).to eq(1500)
      end

      it "refuses a post without the confirmed price (no other-priced coupon is picked)" do
        credit_cc!(user, 2000)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 1000)
        expect { post discount_codes_path, params: { dollar_cost: 10 } }.not_to change(CcMoney, :count)
        expect(response).to redirect_to(new_discount_code_path)
        expect(coupon.reload.user_id).to be_nil
      end

      it "the offers page posts both the dollar value and the price of each offer" do
        create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 500)
        create(:coupon_code, :unclaimed, dollar_cost: 10, cc_cost: 1000)
        get new_discount_code_path
        expect(response.body).to include(discount_codes_path(dollar_cost: 10, cc_cost: 500).gsub("&", "&amp;"))
        expect(response.body).to include(discount_codes_path(dollar_cost: 10, cc_cost: 1000).gsub("&", "&amp;"))
      end

      it "a legacy negative-price coupon answers 'not created properly', not a 500 (nothing charged)" do
        credit_cc!(user, 100)
        coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 10)
        coupon.update_column(:cc_cost, -10)
        post discount_codes_path, params: { dollar_cost: 5, cc_cost: -10 }
        expect(response).to redirect_to(discount_codes_path)
        expect(flash[:alert]).to eq("Discount Code not created properly!")
        expect(coupon.reload.user_id).to be_nil
        expect(user.reload.wallet).to eq(100)
      end

      it "is available to staff and admin with the same economics" do
        [staff, admin].each do |u|
          get logout_path
          shop_log_in!(u)
          credit_cc!(u, 50)
          coupon = create(:coupon_code, :unclaimed, dollar_cost: 7, cc_cost: 20)
          post discount_codes_path, params: { dollar_cost: 7, cc_cost: 20 }
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
      expect(response).to redirect_to(login_path)
      delete coupon_code_path(coupon)
      expect(response).to redirect_to(login_path)
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

      it "refuses a negative price on create (422, nothing saved) and on update (422, unchanged)" do
        expect do
          post coupon_codes_path, params: { coupon_code: { code: "NEG", cc_cost: -5, dollar_cost: 3 } }
        end.not_to change(CouponCode, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Cc cost must be greater than or equal to 0")

        patch coupon_code_path(coupon), params: { coupon_code: { cc_cost: -1 } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(coupon.reload.cc_cost).not_to eq(-1)
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
        expect(response.body).to match(%r{<form[^>]*action="#{redeem_cc_moneys_path}"[^>]*method="post"})
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

      it "redirects with the generic alert for a validly signed token whose cc_money row no longer exists" do
        stale = verifier.generate(999_999_999)
        shop_log_in!(user)
        get link_cc_to_user_cc_moneys_path, params: { token: stale }
        # FIXED(D-S14): a missing row gets the same alert as an invalid token instead of a NoMethodError 500
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to start_with("Something went wrong.")
      end
    end

    describe "POST /cc_moneys/redeem" do
      it "does not link on a plain GET (the mailed link only opens the confirm page)" do
        shop_log_in!(user)
        get "/cc_moneys/redeem", params: { token: token, user: { email: user.email } }
        expect(unlinked.reload.linked).to be(false)
        expect(user.cc_moneys.sum(:cc)).to eq(0)
      end

      it "redirects guests to login and changes nothing" do
        post redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        expect(response.location).to include("/login")
        expect(unlinked.reload.linked).to be(false)
      end

      it "links the points to the user whose email is submitted" do
        shop_log_in!(user)
        post redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:notice]).to eq("The CC Money has been added to #{user.name}")
        expect(unlinked.reload.user_id).to eq(user.id)
        expect(unlinked.linked).to be(true)
        expect(user.cc_moneys.sum(:cc)).to eq(20)
      end

      it "lets a signed-in user credit the points to ANY account by typing its email" do
        shop_log_in!(user)
        post redeem_cc_moneys_path, params: { token: token, user: { email: other.email } }
        # INTENDED(D-S15): crediting the typed email is deliberate (guest purchasers credit their account by email); no behavior change. FIXED(D-S15, GET half): redeem is POST only; the mailed link opens link_cc_to_user (a GET confirm page with the POST form)
        expect(flash[:notice]).to eq("The CC Money has been added to #{other.name}")
        expect(unlinked.reload.user_id).to eq(other.id)
      end

      it "is single-use: a second redeem alerts and keeps the first owner" do
        shop_log_in!(user)
        post redeem_cc_moneys_path, params: { token: token, user: { email: user.email } }
        post redeem_cc_moneys_path, params: { token: token, user: { email: other.email } }
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
        expect(unlinked.reload.user_id).to eq(user.id)
      end

      it "unknown email: misleading 'already added' alert, points stay unlinked" do
        shop_log_in!(user)
        post redeem_cc_moneys_path, params: { token: token, user: { email: "nobody@example.com" } }
        expect(response).to redirect_to(cc_moneys_path)
        # INTENDED(D-S16): keep the existing alert for an unknown email (user decision: crediting a typed email is intended); no behavior change
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
        expect(unlinked.reload.linked).to be(false)
      end

      it "redirects with the generic alert for a validly signed token whose cc_money row no longer exists" do
        stale = verifier.generate(999_999_999)
        shop_log_in!(user)
        post redeem_cc_moneys_path, params: { token: stale, user: { email: user.email } }
        # FIXED(D-S14): same alert as an invalid token instead of a NoMethodError 500
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to start_with("Something went wrong.")
        expect(user.cc_moneys.sum(:cc)).to eq(0)
      end

      it "tampered or garbage token gets the generic alert (no 500) and missing user param is a 302 to root" do
        shop_log_in!(user)
        # FIXED: redeem used verifier.verify (InvalidSignature 500); verified returns nil, handled like a missing row
        post redeem_cc_moneys_path, params: { token: "bad", user: { email: user.email } }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to start_with("Something went wrong.")
        post redeem_cc_moneys_path, params: { user: { email: user.email } }
        expect(response).to redirect_to(cc_moneys_path)
        expect(flash[:alert]).to start_with("Something went wrong.")
        post redeem_cc_moneys_path, params: { token: token }
        expect(response).to redirect_to(root_path)
        expect(unlinked.reload.linked).to be(false)
      end
    end
  end
end
