require "rails_helper"

RSpec.describe CcMoneysController, type: :controller do
  describe "GET /index" do
    context "not logged in" do
      it "should return 200 response" do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /link_cc_to_user" do
    context "logged in" do
      before(:each) do
        @user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
      end

      it "should return 200 response with token" do
        new_cc = CcMoney.create(cc: 10, linked: false, purchaser_email: @user.email)
        hash = new_cc.claim_token
        get :link_cc_to_user, params: { token: hash }
        expect(response).to have_http_status(:success)
      end

      it "should redirect without token" do
        get :link_cc_to_user
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:alert]).to eq("This link is not valid. Open the link from your email again, or contact uottawa.makerepo@gmail.com.")
      end
    end
  end

  describe "POST /redeem" do
    context "logged in" do
      before(:each) do
        @user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10_000
        @new_cc = CcMoney.create(cc: 10, linked: false, purchaser_email: @user.email)
        @hash = @new_cc.claim_token
      end

      it "should put the cc in the wallet" do
        post :redeem, params: { token: @hash }
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:notice]).to eq(
          "The CC Money has been added to #{@user.name}"
        )
        expect(User.find(@user.id).cc_moneys.sum(:cc)).to eq(10)
      end

      it "should not put the cc in the wallet (already used)" do
        CcMoney.last.update(linked: true)
        post :redeem, params: { token: @hash }
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:alert]).to eq(
          "The CC Money has already been added to an account"
        )
      end
    end
  end
end
