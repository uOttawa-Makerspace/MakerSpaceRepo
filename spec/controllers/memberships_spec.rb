require 'rails_helper'

RSpec.describe MembershipsController, type: :controller do
  before :each do
    @admin = create(:user, :admin)
    @regular_user = create(:user, :regular_user)
    session[:user_id] = @regular_user.id
    session[:expires_at] = Time.zone.now + 10_000

    @tier = create(:membership_tier, title_en: "1 Month Membership", duration: 1.month.to_i, internal_price: 30, 
external_price: 30)
  end

  describe "GET #your_memberships" do
    it "assigns memberships and a new membership" do
      membership = create(:membership, user: @regular_user, membership_tier: @tier, status: 'paid')
      get :your_memberships
      expect(assigns(:memberships)).to include(membership)
      expect(assigns(:membership)).to be_a_new(Membership)
      expect(response).to render_template(:your_memberships)
    end
  end

  describe "POST #create" do
    context "when user is not cutoff" do
      it "creates a membership and redirects to checkout_link" do
        allow_any_instance_of(MembershipsController).to receive(:is_user_cutoff).and_return(false)
        allow_any_instance_of(Membership).to receive(:checkout_link).and_return("https://checkout.example.com")

        post :create, params: { membership: { membership_tier_id: @tier.id } }

        membership = Membership.last
        expect(membership.user).to eq(@regular_user)
        expect(membership.membership_tier).to eq(@tier)
        expect(response).to redirect_to("https://checkout.example.com")
      end
    end

    context "when user is cutoff" do
      it "renders index with flash alert" do
        allow_any_instance_of(MembershipsController).to receive(:is_user_cutoff).and_return(true)
        post :create, params: { membership: { membership_tier_id: @tier.id } }
        expect(flash.now[:alert]).to eq(I18n.t('memberships.index.purchase.cutoff_tooltip'))
      end
    end
  end

  describe "POST #admin_create_membership" do
    before :each do
      session[:user_id] = @admin.id
      session[:expires_at] = Time.zone.now + 10_000
    end

    context "when user is admin" do
      it "creates a custom membership" do
        create(:membership_tier, title_en: "Custom Membership", duration: 1.hour.to_i)
        expect do
          post :admin_create_membership, params: { user_id: @regular_user.id, extend_days: 5 }
        end.to change { @regular_user.memberships.count }.by(1)
        expect(flash[:notice]).to include("Custom membership added")
      end
    end

    context "when user is not admin" do
      before :each do
        session[:user_id] = @regular_user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "returns unauthorized" do
        post :admin_create_membership, params: { user_id: @regular_user.id, extend_days: 5 }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
