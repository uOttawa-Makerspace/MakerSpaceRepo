require 'rails_helper'

RSpec.describe CcMoneysController, type: :controller do
  describe "GET /index" do
    context 'logged as admin' do
      it 'should return 200 response' do
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end
end

