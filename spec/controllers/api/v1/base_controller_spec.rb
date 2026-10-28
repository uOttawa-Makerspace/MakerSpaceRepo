# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :controller do
  controller(Api::V1::BaseController) do
    before_action :authenticate!, only: :index
    before_action :require_staff!, only: :show
    before_action :require_admin!, only: :update

    def index = render(json: { id: current_user.id })
    def show = render(json: { ok: true })
    def update = render(json: { ok: true })
    def create = raise(ActiveRecord::RecordNotFound)
    def destroy = params.require(:thing)
    def edit
      u = User.new
      u.valid?
      raise ActiveRecord::RecordInvalid, u
    end
  end

  before do
    routes.draw do
      get "anonymous" => "api/v1/base#index"
      get "anonymous/show" => "api/v1/base#show"
      put "anonymous/update" => "api/v1/base#update"
      post "anonymous/create" => "api/v1/base#create"
      delete "anonymous/destroy" => "api/v1/base#destroy"
      get "anonymous/edit" => "api/v1/base#edit"
    end
  end

  let(:user) { create(:user) }
  let(:error) { response.parsed_body["error"] }

  def bearer(token, scheme: "Bearer") = request.headers["Authorization"] = "#{scheme} #{token}"

  describe "authentication" do
    it "401s without a header, with the uniform error body and a challenge" do
      get :index
      expect(response).to have_http_status(:unauthorized)
      expect(error).to eq("code" => "unauthenticated", "message" => "Authentication required")
      expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
    end

    it "accepts a valid access token" do
      bearer(ApiAccessToken.issue(user).first)
      get :index
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(user.id)
    end

    it "checks the scheme word" do
      bearer(ApiAccessToken.issue(user).first, scheme: "Basic")
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a header without a scheme word" do
      request.headers["Authorization"] = ApiAccessToken.issue(user).first
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an expired token" do
      jwt, = ApiAccessToken.issue(user, now: 20.minutes.ago)
      bearer(jwt)
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a stale token_version" do
      jwt, = ApiAccessToken.issue(user)
      user.update_columns(token_version: user.token_version + 1)
      bearer(jwt)
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses soft-deleted and inactive users" do
      jwt, = ApiAccessToken.issue(user)
      bearer(jwt)
      user.update_columns(active: false)
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a deleted user" do
      jwt, = ApiAccessToken.issue(user)
      user.update_columns(deleted: true)
      bearer(jwt)
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token signed with another key" do
      bearer(JWT.encode({ user_id: user.id, ver: user.token_version, typ: "access", exp: 5.minutes.from_now.to_i }, "nope", "HS256"))
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token without typ access (the legacy 14-day token)" do
      bearer(user.token)
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "never writes the session or a cookie" do
      bearer(ApiAccessToken.issue(user).first)
      get :index
      expect(session[:user_id]).to be_nil
      expect(response.headers["Set-Cookie"]).to be_nil
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end
  end

  describe "roles" do
    it "403s a regular user on require_staff!" do
      bearer(ApiAccessToken.issue(user).first)
      get :show
      expect(response).to have_http_status(:forbidden)
      expect(error["code"]).to eq("forbidden")
    end

    it "lets staff and admin through require_staff!" do
      %w[staff admin].each do |role|
        bearer(ApiAccessToken.issue(create(:user, role: role)).first)
        get :show
        expect(response).to have_http_status(:ok)
      end
    end

    it "401s an anonymous caller before looking at roles" do
      get :show
      expect(response).to have_http_status(:unauthorized)
    end

    it "403s staff on require_admin! and lets an admin through" do
      bearer(ApiAccessToken.issue(create(:user, role: "staff")).first)
      put :update
      expect(response).to have_http_status(:forbidden)

      bearer(ApiAccessToken.issue(create(:user, role: "admin")).first)
      put :update
      expect(response).to have_http_status(:ok)
    end
  end

  describe "rescued errors" do
    it "404s RecordNotFound" do
      post :create
      expect(response).to have_http_status(:not_found)
      expect(error["code"]).to eq("not_found")
    end

    it "422s ParameterMissing with the field" do
      delete :destroy
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("parameter_missing")
      expect(error["fields"]).to eq("thing" => ["is required"])
    end

    it "422s RecordInvalid with field errors" do
      get :edit
      expect(response).to have_http_status(:unprocessable_content)
      expect(error["code"]).to eq("validation_failed")
      expect(error["fields"]).to be_a(Hash).and include("email")
    end
  end
end
