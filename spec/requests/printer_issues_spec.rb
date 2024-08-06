require "rails_helper"

RSpec.describe "PrinterIssues", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/printer_issues/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get "/printer_issues/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/printer_issues/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/printer_issues/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/printer_issues/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/printer_issues/update"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /destroy" do
    it "returns http success" do
      get "/printer_issues/destroy"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /history" do
    it "returns http success" do
      get "/printer_issues/history"
      expect(response).to have_http_status(:success)
    end
  end
end
