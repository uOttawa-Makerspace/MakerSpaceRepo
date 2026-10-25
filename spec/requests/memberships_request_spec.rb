# frozen_string_literal: true

require "rails_helper"

# Characterization of memberships: public marketing page, purchase via a Shopify
# draft order (GraphQL stubbed with ShopSpecHelpers::FakeShopifyAdmin), the
# admin extend/revoke actions and the admin tier editor.
RSpec.describe "Memberships (HTTP contract)", type: :request do
  let(:user) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let!(:tier) do
    create(:membership_tier, title_en: "1 Semester Membership", title_fr: "Adhesion 1 semestre",
                             duration: 120, internal_price: 25, external_price: 40)
  end

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  # ------------------------------------------------------------------ index

  describe "GET /memberships" do
    it "is public (guests included) when the default tiers exist" do
      get memberships_path
      expect(response).to have_http_status(:ok)
    end

    it "500s on a fresh install with no tiers at all" do
      MembershipTier.delete_all
      # WART(D-S22): the landing page dereferences the looked-up tiers without a nil guard, so it is a 500 until at least two tiers exist
      get memberships_path
      expect(response).to have_http_status(:internal_server_error)
    end

    it "renders for a signed-in user" do
      shop_log_in!(user)
      get memberships_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ------------------------------------------------------ your_memberships

  describe "GET /memberships/your_memberships" do
    it "redirects guests to login" do
      get your_memberships_memberships_path
      expect(response).to redirect_to(login_path(back_to: "/memberships/your_memberships"))
    end

    it "lists only the user's PAID memberships; pending/revoked are hidden" do
      paid = create(:membership, user: user, membership_tier: tier, status: "paid")
      pending = create(:membership, user: user, membership_tier: create(:membership_tier, title_en: "Pending Tier"), status: "pending")
      revoked = create(:membership, user: user, membership_tier: create(:membership_tier, title_en: "Revoked Tier"), status: "revoked")
      theirs = create(:membership, user: other, membership_tier: create(:membership_tier, title_en: "Their Tier"), status: "paid")
      shop_log_in!(user)
      get your_memberships_memberships_path
      expect(response).to have_http_status(:ok)
      memberships = controller.instance_variable_get(:@memberships)
      expect(memberships).to contain_exactly(paid)
      expect(memberships).not_to include(pending, revoked, theirs)
    end

    it "marks the user as cut off when an active membership already reaches the cutoff date" do
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 3.years.from_now)
      shop_log_in!(user)
      get your_memberships_memberships_path
      expect(controller.instance_variable_get(:@is_user_cutoff)).to be(true)
    end

    it "is not cut off with no active membership" do
      shop_log_in!(user)
      get your_memberships_memberships_path
      expect(controller.instance_variable_get(:@is_user_cutoff)).to be(false)
    end
  end

  # ------------------------------------------------------------------ purchase

  describe "POST /memberships" do
    it "redirects guests to login without creating anything" do
      expect { post memberships_path, params: { membership: { membership_tier_id: tier.id } } }
        .not_to change(Membership, :count)
      expect(response).to redirect_to(login_path(back_to: "/memberships"))
    end

    context "signed in" do
      let!(:admin_client) { stub_shopify_admin! }
      before { shop_log_in!(user) }

      it "creates a pending membership with dates, a Shopify draft order, and redirects to its invoice URL" do
        freeze = Time.utc(2026, 3, 1, 12)
        travel_to(freeze) do
          expect { post memberships_path, params: { membership: { membership_tier_id: tier.id } } }
            .to change(Membership, :count).by(1)
        end
        expect(response).to have_http_status(:found)
        expect(response.location).to eq("https://shop.example.test/invoices/abc")

        m = Membership.last
        expect(m.user).to eq(user)
        expect(m.status).to eq("pending")
        expect(m.start_date).to eq(freeze)
        expect(m.end_date).to eq(Time.zone.at(freeze) + 120.days) # wall-clock days in the app zone (DST aware)
        expect(m.shopify_draft_order_id).to eq("gid://shopify/DraftOrder/9001")

        create_call = admin_client.calls.find { |c| c[:query].include?("draftOrderCreate") }
        input = create_call[:variables][:input]
        expect(input[:tags]).to eq(["makerepo_test_membership"])
        expect(input[:lineItems]).to eq([{ originalUnitPrice: "40.0", quantity: 1, title: "1 Semester Membership" }])
        expect(input[:metafields]).to eq([{ namespace: "makerepo", key: "membership_db_reference",
                                            value: m.id.to_s, type: "number_integer" }])
      end

      it "charges the internal price to internal identities" do
        user.update_column(:identity, User::INTERNAL_IDENTITIES.first)
        post memberships_path, params: { membership: { membership_tier_id: tier.id } }
        create_call = admin_client.calls.find { |c| c[:query].include?("draftOrderCreate") }
        expect(create_call[:variables][:input][:lineItems].first[:originalUnitPrice]).to eq("25.0")
      end

      it "starts a new membership when the previous active one ends (stacked dates)" do
        prior_end = 10.days.from_now.change(usec: 0)
        create(:membership, user: user, membership_tier: tier, status: "paid", end_date: prior_end)
        post memberships_path, params: { membership: { membership_tier_id: tier.id } }
        m = Membership.order(:id).last
        expect(m.start_date).to be_within(1.second).of(prior_end)
        expect(m.end_date).to be_within(1.second).of(prior_end + 120.days)
      end

      it "when Shopify fails: destroys the pending row, then 500s while re-rendering :index" do
        admin_client.user_errors = [{ "message" => "boom" }]
        # WART(D-S23): the failure path does `render :index` but only #index sets @membership_day/@membership_sem, so the intended "Error creating membership" alert page is a 500
        expect { post memberships_path, params: { membership: { membership_tier_id: tier.id } } }
          .not_to change(Membership, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "a faculty tier 500s and leaves an orphan pending membership" do
        faculty = create(:membership_tier, title_en: "Faculty Membership", duration: 365)
        # WART(D-S18): Membership#checkout_link calls `flash` (a controller method) for the faculty guard; this recurses until SystemStackError, which `rescue StandardError` does not catch, so the user gets a 500 and the pending row is never cleaned up
        expect { post memberships_path, params: { membership: { membership_tier_id: faculty.id } } }
          .to change(Membership, :count).by(1)
        expect(response).to have_http_status(:internal_server_error)
        expect(Membership.last.status).to eq("pending")
        expect(Membership.last.shopify_draft_order_id).to be_nil
        expect(admin_client.calls).to be_empty
      end

      it "accepts ANY tier id, hidden tiers included" do
        hidden = create(:membership_tier, title_en: "Hidden Tier", hidden: true, duration: 30)
        # WART(D-S19): purchase does not check MembershipTier#hidden (nor that the tier is purchasable, e.g. "Custom Membership")
        post memberships_path, params: { membership: { membership_tier_id: hidden.id } }
        expect(response.location).to eq("https://shop.example.test/invoices/abc")
        expect(Membership.last.membership_tier).to eq(hidden)
      end

      it "unknown tier id: no row, and the error page is the same 500 as D-S23" do
        expect { post memberships_path, params: { membership: { membership_tier_id: 999_999 } } }
          .not_to change(Membership, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "missing membership param redirects to root with the ParameterMissing message" do
        post memberships_path, params: {}
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("membership")
      end

      it "refuses a purchase when the user is cut off (active membership ends >= 1y ahead)" do
        create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 3.years.from_now)
        expect { post memberships_path, params: { membership: { membership_tier_id: tier.id } } }
          .not_to change(Membership, :count)
        # WART(D-S20): the cutoff branch sets flash.now and returns with no render/redirect, so the browser gets an empty 204 and no visible message
        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_blank
        expect(admin_client.calls).to be_empty
      end
    end
  end

  # ------------------------------------------------------ admin extend / revoke

  describe "POST /memberships/admin_create_membership" do
    let!(:custom) { create(:membership_tier, title_en: "Custom Membership", duration: 1) }
    let(:params) { { user_id: other.id, extend_days: 5 } }

    it "sends guests to login" do
      post admin_create_membership_memberships_path, params: params
      expect(response).to redirect_to(login_path(back_to: "/memberships/admin_create_membership"))
    end

    it "answers a bare 401 to regular users and staff and creates nothing" do
      [user, staff].each do |u|
        get logout_path
        shop_log_in!(u)
        expect { post admin_create_membership_memberships_path, params: params }.not_to change(Membership, :count)
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to be_blank
      end
    end

    context "as admin" do
      before { shop_log_in!(admin) }

      it "adds a paid Custom Membership of N days starting now when the user has none" do
        freeze = Time.utc(2026, 3, 1, 12)
        travel_to(freeze) do
          expect { post admin_create_membership_memberships_path, params: params }
            .to change { other.memberships.count }.by(1)
        end
        expect(response).to redirect_to(memberships_path)
        expect(flash[:notice]).to eq("Custom membership added for 5 days.")
        m = other.memberships.last
        expect(m.status).to eq("paid")
        expect(m.membership_tier).to eq(custom)
        expect(m.start_date).to eq(freeze)
        expect(m.end_date).to eq(freeze + 5.days)
      end

      it "stacks after the user's latest active membership" do
        base_end = 20.days.from_now.change(usec: 0)
        create(:membership, user: other, membership_tier: tier, status: "paid", end_date: base_end)
        post admin_create_membership_memberships_path, params: params
        m = other.memberships.order(:id).last
        expect(m.start_date).to be_within(1.second).of(base_end)
        expect(m.end_date).to be_within(1.second).of(base_end + 5.days)
      end

      it "rejects zero/blank/negative days with an alert" do
        ["0", "", "-3", "abc"].each do |days|
          expect { post admin_create_membership_memberships_path, params: { user_id: other.id, extend_days: days } }
            .not_to change(Membership, :count)
          expect(flash[:alert]).to eq("Please enter a valid number of days.")
        end
      end

      it "redirects back to the referer when given one" do
        post admin_create_membership_memberships_path, params: params, headers: { "HTTP_REFERER" => "http://www.example.com/admin/users" }
        expect(response).to redirect_to("http://www.example.com/admin/users")
      end

      it "404s for an unknown user" do
        post admin_create_membership_memberships_path, params: { user_id: 0, extend_days: 2 }
        expect(response).to have_http_status(:not_found)
      end

      it "404s when the 'Custom Membership' tier does not exist" do
        custom.destroy
        expect { post admin_create_membership_memberships_path, params: params }.not_to change(Membership, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /memberships/:id/revoke" do
    let!(:membership) { create(:membership, user: other, membership_tier: tier, status: "paid") }

    it "sends guests to login and leaves the membership alone" do
      patch revoke_membership_path(membership)
      expect(response).to redirect_to(login_path(back_to: "/memberships/#{membership.id}/revoke"))
      expect(membership.reload.status).to eq("paid")
    end

    it "lets ANY signed-in user revoke ANY membership" do
      shop_log_in!(user)
      patch revoke_membership_path(membership)
      # WART(D-S21): revoke has no admin or ownership check (only admin_create_membership is gated); any signed-in user can revoke anyone's paid membership by id
      expect(response).to redirect_to(memberships_path)
      expect(flash[:notice]).to eq("Membership revoked successfully.")
      expect(membership.reload.status).to eq("revoked")
      expect(other.memberships.active).to be_empty
    end

    it "works for staff and admin, redirecting back to the referer" do
      shop_log_in!(admin)
      patch revoke_membership_path(membership), headers: { "HTTP_REFERER" => "http://www.example.com/admin/users/1" }
      expect(response).to redirect_to("http://www.example.com/admin/users/1")
      expect(membership.reload.status).to eq("revoked")
    end

    it "404s for an unknown id" do
      shop_log_in!(admin)
      patch revoke_membership_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------- admin tier editor

  describe "Admin::MembershipsController" do
    it "redirects guests to login and non-admins (user, staff) to root" do
      get admin_memberships_path
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/")
      [user, staff].each do |u|
        get logout_path
        shop_log_in!(u)
        get admin_memberships_path
        expect(response).to redirect_to("/")
        patch admin_membership_path(tier), params: { membership_tier: { internal_price: 0 } }
        expect(response).to redirect_to("/")
        expect(tier.reload.internal_price).to eq(25)
      end
    end

    context "as admin" do
      before { shop_log_in!(admin) }

      it "lists tiers ordered by id" do
        second = create(:membership_tier, title_en: "Zed Tier")
        get admin_memberships_path
        expect(response).to have_http_status(:ok)
        expect(response.body.index("1 Semester Membership")).to be < response.body.index("Zed Tier")
        expect(second).to be_persisted
      end

      it "updates a tier and flashes success (flash[:success], not notice)" do
        patch admin_membership_path(tier), params: { membership_tier: {
          title_en: "Renamed", title_fr: "Renomme", internal_price: 10, external_price: 20, duration: 90, hidden: true
        } }
        expect(response).to redirect_to(admin_memberships_path)
        expect(flash[:success]).to eq("Membership tier updated successfully.")
        tier.reload
        expect([tier.title_en, tier.title_fr, tier.internal_price, tier.external_price, tier.duration, tier.hidden])
          .to eq(["Renamed", "Renomme", 10, 20, 90, true])
      end

      it "flashes the validation errors and keeps the tier on invalid input" do
        patch admin_membership_path(tier), params: { membership_tier: { title_en: "", duration: 0, internal_price: -1 } }
        expect(response).to redirect_to(admin_memberships_path)
        expect(flash[:alert]).to include("Title en This field is required.")
        expect(flash[:alert]).to include("Duration must be greater than 0")
        expect(flash[:alert]).to include("Internal price must be greater than or equal to 0")
        expect(tier.reload.title_en).to eq("1 Semester Membership")
      end

      it "404s for an unknown tier" do
        patch admin_membership_path(0), params: { membership_tier: { title_en: "x" } }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
