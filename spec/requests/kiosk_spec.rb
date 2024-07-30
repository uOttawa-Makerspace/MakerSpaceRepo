require "rails_helper"

RSpec.describe "Kiosks", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/kiosk/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/kiosk/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/kiosk/edit"
      expect(response).to have_http_status(:success)
    end
  end
end
