require 'rails_helper'

RSpec.describe CcMoneysController, type: :controller do
  describe "GET /index" do
    context 'not logged in' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /link_cc_to_user" do
    context 'logged in' do

      before(:each) do
        user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = user.id
        session[:expires_at] = Time.zone.now + 10000
      end

      it 'should return 200 response with token' do
        new_cc = CcMoney.create(cc: 10, linked: false)
        hash = Rails.application.message_verifier(:cc).generate(new_cc.id)
        get :link_cc_to_user, params: {token: hash}
        expect(response).to have_http_status(:success)
      end

      it 'should redirect without token' do
        get :link_cc_to_user
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:alert]).to eq("Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com")
      end
    end
  end

  describe "GET /redeem" do
    context 'logged in' do

      before(:each) do
        @user = create(:user, :volunteer_with_dev_program)
        session[:user_id] = @user.id
        session[:expires_at] = Time.zone.now + 10000
        @new_cc = CcMoney.create(cc: 10, linked: false)
        @hash = Rails.application.message_verifier(:cc).generate(@new_cc.id)
      end

      it 'should put the cc in the wallet' do
        get :redeem, params: {token: @hash, user: {email: @user.email}}
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:notice]).to eq("The CC Money has been added to #{@user.name}")
        expect(User.find(@user.id).cc_moneys.sum(:cc)).to eq(10)
      end

      it 'should not put the cc in the wallet (already used)' do
        CcMoney.last.update(linked: true)
        get :redeem, params: {token: @hash, user: {email: @user.email}}
        expect(response).to redirect_to cc_moneys_path
        expect(flash[:alert]).to eq("The CC Money has already been added to an account")
      end

    end
  end

end

