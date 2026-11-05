# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/spaces.md
RSpec.describe "/api/v1 spaces and /api/v1/me/space", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user) }
  let!(:space_a) { create(:space, name: "Alpha Lab") }
  let!(:space_b) { create(:space, name: "Beta Lab") }

  def body = response.parsed_body
  def error = body["error"]
  def auth(user) = { "Authorization" => "Bearer #{ApiAccessToken.issue(user).first}" }
  def api_get(path, as: nil) = get(path, headers: json_headers.merge(as ? auth(as) : {}))
  def api_send(verb, path, payload, as: nil) = public_send(verb, path, params: payload.to_json, headers: json_headers.merge(as ? auth(as) : {}))

  describe "GET /api/v1/spaces" do
    it "401s a guest and 403s a regular user" do
      api_get "/api/v1/spaces"
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/spaces", as: regular
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
    end

    it "lists every space as exactly {id, name}, by name, for staff and admin" do
      create(:space, name: "Gamma Lab", keycode: "9999") if Space.column_names.include?("keycode")
      [staff, admin].each do |caller|
        api_get "/api/v1/spaces", as: caller
        expect(response).to have_http_status(:ok)
        expect(body).to eq(Space.order(:name).map { |s| { "id" => s.id, "name" => s.name } })
        expect(body.map(&:keys).uniq).to eq([%w[id name]])
      end
      expect(body.map { |s| s["name"] }).to include("Alpha Lab", "Beta Lab")
    end
  end

  describe "GET /api/v1/me/space" do
    it "401s a guest and 403s a regular user" do
      api_get "/api/v1/me/space"
      expect(response).to have_http_status(:unauthorized)
      api_get "/api/v1/me/space", as: regular
      expect(response).to have_http_status(:forbidden)
    end

    it "answers the assigned space as {id, name}" do
      staff.update_columns(space_id: space_b.id)
      api_get "/api/v1/me/space", as: staff
      expect(response).to have_http_status(:ok)
      expect(body).to eq("id" => space_b.id, "name" => "Beta Lab")
    end

    it "falls back to the first space when none is assigned (as the legacy dashboard does)" do
      api_get "/api/v1/me/space", as: admin
      expect(response).to have_http_status(:ok)
      expect(body).to eq("id" => Space.first.id, "name" => Space.first.name)
      expect(body.keys).to eq(%w[id name])
    end

    it "404s when there is no space at all" do
      User.update_all(space_id: nil)
      LabSession.delete_all
      Space.destroy_all
      api_get "/api/v1/me/space", as: staff
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end
  end

  describe "PUT /api/v1/me/space" do
    it "401s a guest and 403s a regular user, changing nothing" do
      api_send :put, "/api/v1/me/space", { space_id: space_a.id }
      expect(response).to have_http_status(:unauthorized)
      api_send :put, "/api/v1/me/space", { space_id: space_a.id }, as: regular
      expect(response).to have_http_status(:forbidden)
      expect(regular.reload.space_id).to be_nil
    end

    it "moves staff and admin to the space and answers {id, name}" do
      [staff, admin].each do |caller|
        api_send :put, "/api/v1/me/space", { space_id: space_a.id }, as: caller
        expect(response).to have_http_status(:ok)
        expect(body).to eq("id" => space_a.id, "name" => "Alpha Lab")
        expect(caller.reload.space_id).to eq(space_a.id)
      end
      api_get "/api/v1/me/space", as: staff
      expect(body["id"]).to eq(space_a.id)
    end

    it "accepts the id as a numeric string" do
      api_send :put, "/api/v1/me/space", { space_id: space_b.id.to_s }, as: staff
      expect(response).to have_http_status(:ok)
      expect(staff.reload.space_id).to eq(space_b.id)
    end

    it "404s an unknown space and leaves the user where they were" do
      staff.update_columns(space_id: space_a.id)
      api_send :put, "/api/v1/me/space", { space_id: 0 }, as: staff
      expect(response).to have_http_status(:not_found)
      api_send :put, "/api/v1/me/space", { space_id: 2_000_000_000_000 }, as: staff
      expect(response).to have_http_status(:not_found)
      expect(staff.reload.space_id).to eq(space_a.id)
    end

    it "422s a missing or malformed space_id" do
      api_send :put, "/api/v1/me/space", {}, as: staff
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      [nil, "abc", "12abc", [1], { "a" => 1 }, 1.5, true, "1" * 40].each do |bad|
        api_send :put, "/api/v1/me/space", { space_id: bad }, as: staff
        expect(response).to have_http_status(:unprocessable_content), "space_id=#{bad.inspect}"
      end
      expect(staff.reload.space_id).to be_nil
    end

    it "400s malformed JSON" do
      put "/api/v1/me/space", params: "{nope", headers: json_headers.merge(auth(staff))
      expect(response).to have_http_status(:bad_request)
    end
  end
end
