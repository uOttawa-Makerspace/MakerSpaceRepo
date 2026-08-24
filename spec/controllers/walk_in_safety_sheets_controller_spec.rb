require 'rails_helper'

RSpec.describe WalkInSafetySheetsController do
  let!(:brunsfield) { Space.find_by(name: "Brunsfield Centre") || create(:space, name: "Brunsfield Centre") }

  let(:current_user) do
    user = create :user
    session[:user_id] = user.id
    session[:expires_at] = Time.zone.now + 10_000
    user
  end

  it 'should ask for login' do
    session[:user_id] = nil
    get :index
    expect(response.redirect_url).to match(login_url)
  end

  describe 'Signing the sheet' do
    it 'should allow logged-in users to access' do
      current_user
      get :index
      expect(response).to have_http_status :success
    end

    it 'should have a sheet for each space' do
      current_user
      space = create(:space)
      get :show, params: { id: space.id }
      expect(response).to have_http_status :success
    end

    it 'should reject sheets that have missing agreements' do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult, space: brunsfield).attributes
      post :create, params: { walk_in_safety_sheet: }
      expect(response).to have_http_status :unprocessable_content
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements * 2
           }
      expect(response).to have_http_status :unprocessable_content
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements.take(3)
           }
      expect(response).to have_http_status :unprocessable_content
    end

    it 'should accept sheets that have all agreements' do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult, space: brunsfield).attributes
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      expect(current_user.walk_in_safety_sheets).to exist
    end

    it 'should reject sheets have have missing info' do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult, space: brunsfield).attributes
      walk_in_safety_sheet[:is_minor] = true
      post :create,
           params: {
             walk_in_safety_sheet:,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :unprocessable_content
      expect(current_user.walk_in_safety_sheets).not_to exist
    end

    it 'should prevent signing a sheet twice for the same space' do
      current_user
      walk_in_safety_sheet = build(:walk_in_safety_sheet, :is_adult, space: brunsfield).attributes
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
      expect(response).to have_http_status :unprocessable_content
      expect(current_user.walk_in_safety_sheets.count).to eq 1
    end

    it 'should alllow signing one sheet for each space' do
      current_user
      other_space = create(:space)
      post :create,
           params: {
             walk_in_safety_sheet:
               build(:walk_in_safety_sheet, :is_adult, space: brunsfield).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      post :create,
           params: {
             walk_in_safety_sheet:
               build(
                 :walk_in_safety_sheet,
                 :is_adult,
                 space: other_space
               ).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      expect(current_user.walk_in_safety_sheets.count).to eq 2
    end
  end

  describe 'storing supervisor information' do
    def compare_supervisors(space:, sheet:)
      space.space_managers.all? do |supervisor|
        sheet.supervisor_names.include?(supervisor.name) &&
          sheet.supervisor_contacts.include?(supervisor.email)
      end
    end

    it 'should get the current supervisors for a space' do
      current_user
      space = create(:space, :with_space_managers)
      post :create,
           params: {
             walk_in_safety_sheet:
               build(:walk_in_safety_sheet, :is_adult, space:).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }
      expect(response).to have_http_status :success
      expect(
        compare_supervisors(
          space:,
          sheet: current_user.reload.walk_in_safety_sheets.last
        )
      ).to be_truthy
    end

    it 'should keep a record of old space supervisors' do
      old_user = current_user
      space = create(:space, :with_space_managers)
      post :create,
           params: {
             walk_in_safety_sheet:
               build(:walk_in_safety_sheet, :is_adult, space:).attributes,
             agreement: WalkInSafetySheetsController.complete_agreements
           }

      expect(
        compare_supervisors(
          space:,
          sheet: current_user.reload.walk_in_safety_sheets.last
        )
      ).to be_truthy

      space.update(space_managers: [create(:user, :admin)])

      other_user = create(:user)
      session[:user_id] = other_user.id

      expect {
        post :create,
             params: {
               walk_in_safety_sheet:
                 build(:walk_in_safety_sheet, :is_adult, space:).attributes,
               agreement: WalkInSafetySheetsController.complete_agreements
             }
      }.not_to change {
        [
          old_user.reload.walk_in_safety_sheets.first.supervisor_names,
          old_user.reload.walk_in_safety_sheets.first.supervisor_contacts
        ]
      }

      expect(
        compare_supervisors(
          space:,
          sheet: other_user.reload.walk_in_safety_sheets.last
        )
      ).to be_truthy
    end
  end
end
