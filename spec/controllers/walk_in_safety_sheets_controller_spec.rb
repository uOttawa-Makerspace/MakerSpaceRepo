require "rails_helper"

RSpec.describe WalkInSafetySheetsController do
  before :all do
    create(:space)
  end

  it "should ask for login" do
    session[:user_id] = nil
    get :index
    expect(response).to redirect_to login_url
  end

  describe "Signing the sheet" do
    let(:current_user) do
      user = create :user
      session[:user_id] = user.id
      session[:expires_at] = Time.zone.now + 10_000
      user
    end

    it "should allow logged-in users to access" do
      current_user
      get :index
      expect(response).to have_http_status :success
    end

    it "should have a sheet for each space" do
      current_user
      space = create(:space)
      get :show, params: { id: space.id }
      expect(response).to have_http_status :success
    end

    it "should reject sheets that have missing agreements" do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult).attributes
      post :create, params: { walk_in_safety_sheet: }
      expect(response).to have_http_status :unprocessable_entity
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements * 2
           }
      expect(response).to have_http_status :unprocessable_entity
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements.take(3)
           }
      expect(response).to have_http_status :unprocessable_entity
    end

    it "should accept sheets that have all agreements" do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult).attributes
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      expect(current_user.walk_in_safety_sheets).to exist
    end

    it "should reject sheets have have missing info" do
      current_user
      # Get an adult sheet
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult).attributes
      # Make it a minor sheet
      walk_in_safety_sheet[:is_minor] = true
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :unprocessable_entity
      expect(current_user.walk_in_safety_sheets).not_to exist
    end

    it "should prevent signing a sheet twice for the same space" do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult).attributes
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(current_user.walk_in_safety_sheets.count).to eq 1
      expect(response).to have_http_status :success
      # Send it again
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :unprocessable_entity
      expect(current_user.walk_in_safety_sheets.count).to eq 1
    end

    it "should alllow signing one sheet for each space" do
      current_user
      post :create, params: {
             walk_in_safety_sheet: build(:walk_in_safety_sheet, :is_adult).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      post :create, params: {
             # make a new space
             walk_in_safety_sheet: build(:walk_in_safety_sheet, :is_adult, space: create(:space)).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      expect(current_user.walk_in_safety_sheets.count).to eq 2
    end
  end
end
