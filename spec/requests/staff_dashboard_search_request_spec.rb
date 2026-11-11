# frozen_string_literal: true

require "rails_helper"

# The React staff app's global search sends GET /staff_dashboard/search?query=...
# with Accept: application/json and an Authorization: Bearer token (no cookie session).
RSpec.describe "Staff dashboard search", type: :request do
  let!(:space) { create(:space) }
  let(:staff) { create(:user, :staff, space: space) }
  let!(:target) { create(:user, :regular_user, name: "Zelda Findable") }
  let(:bearer) { { "Authorization" => "Bearer #{staff.token}", "Accept" => "application/json" } }
  let(:keys) { User.column_names - %w[password access_token] }

  def expect_matching_users
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body.map { |u| u["id"] }).to eq([target.id])
    expect(response.parsed_body.first.keys).to match_array(keys)
  end

  it "answers the staff app's Bearer request (no .json suffix, Accept header)" do
    get "/staff_dashboard/search", params: { query: "Findable" }, headers: bearer
    expect_matching_users
  end

  it "answers the same through the .json suffix" do
    get "/staff_dashboard/search.json", params: { query: "Findable" }, headers: bearer
    expect_matching_users
  end

  it "answers a signed-in browser session asking for JSON" do
    log_in!(staff)
    get "/staff_dashboard/search.json", params: { query: "Findable" }
    expect_matching_users
  end

  it "answers {error: 'no params'} to a blank query over Bearer" do
    get "/staff_dashboard/search", params: { query: "" }, headers: bearer
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("error" => "no params")
  end

  it "renders the HTML results page for a browser session" do
    log_in!(staff)
    get "/staff_dashboard/search", params: { query: "Findable" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Zelda Findable")
  end
end
