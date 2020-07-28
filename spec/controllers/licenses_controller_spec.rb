require 'rails_helper'

RSpec.describe LicensesController, type: :controller do
  before(:all) do
    @user = create(:user, :regular_user)
  end

  before(:each) do
    session[:user_id] = @user.id
  end

  describe "GET /common-creative-attribution" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :common_creative_attribution
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /common_creative_attribution_share_alike" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :common_creative_attribution_share_alike
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /common_creative_attribution_no_derivatives" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :common_creative_attribution_no_derivatives
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /common_creative_attribution_non_commercial" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :common_creative_attribution_non_commercial
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /attribution_non_commercial_share_alike" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :attribution_non_commercial_share_alike
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /attribution_non_commercial_no_derivatives" do
    context 'logged as regular user' do
      it 'should return 200 response' do
        get :attribution_non_commercial_no_derivatives
        expect(response).to have_http_status(:success)
      end
    end
  end
end

