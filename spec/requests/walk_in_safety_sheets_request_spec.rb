# frozen_string_literal: true

require "rails_helper"

# Chunk 17: WalkInSafetySheetsController. before_action :signed_in is the only
# gate; there is no staff/admin view of anybody's sheet. Every action works on
# current_user's own sheet(s) (find_or_initialize_by(user:) /
# current_user.walk_in_safety_sheets), so no endpoint can show another user's
# submission; the route has no JSON or index-of-all.
RSpec.describe "Walk-in safety sheets", type: :request do
  let!(:space) { create(:space) }
  let(:agreements) { WalkInSafetySheetsController.complete_agreements }

  def sheet_params(**over)
    { space_id: space.id, is_minor: false, participant_signature: "Pat Doe",
      participant_telephone_at_home: "613-555-0100",
      emergency_contact_name: "Sam Doe", emergency_contact_telephone: "613-555-0101" }.merge(over)
  end

  def sign!(params: {}, agreement: agreements)
    post walk_in_safety_sheets_path, params: { walk_in_safety_sheet: sheet_params(**params), agreement: agreement }
  end

  it "sends a guest to login (with back_to) for every action, creating nothing" do
    sheet = create(:walk_in_safety_sheet, :is_adult, user: create(:user, :regular_user), space: space)
    [
      -> { get walk_in_safety_sheets_path }, -> { get "/walk_in_safety_sheets/new" },
      -> { get walk_in_safety_sheet_path(space.id) },
      -> { post walk_in_safety_sheets_path, params: { walk_in_safety_sheet: sheet_params, agreement: agreements } },
      -> { patch walk_in_safety_sheet_path(sheet), params: { walk_in_safety_sheet: { emergency_contact_name: "x" } } }
    ].each do |call|
      instance_exec(&call)
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
    end
    expect(WalkInSafetySheet.count).to eq(1)
    expect(sheet.reload.emergency_contact_name).not_to eq("x")
  end

  # the new action/route (always 406, no template) was removed; /new now falls to show,
  # which renders the form.
  it "renders the form on /new for a signed-in user (served by show)" do
    sign_in_as(:regular)
    get "/walk_in_safety_sheets/new"
    expect(response).to have_http_status(:ok)
  end

  it "renders the (unsigned) form for a signed-in user on index and show" do
    %i[regular staff admin].each do |role|
      sign_in_as(role)
      get walk_in_safety_sheets_path
      expect(response).to have_http_status(:ok), role.to_s
      get walk_in_safety_sheet_path(space.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Signed on")
      post logout_path
    end
  end

  it "creates a sheet for the signed-in user and answers 201 with the signed view" do
    user = sign_in_as(:regular)
    expect { sign! }.to change { user.walk_in_safety_sheets.count }.by(1)
    expect(response).to have_http_status(:created)
    expect(response.body).to include("Signed on")
    expect(user.walk_in_safety_sheets.last).to have_attributes(
      space_id: space.id, is_minor: false, participant_signature: "Pat Doe", emergency_contact_name: "Sam Doe"
    )
  end

  it "ignores a user_id (and supervisor columns) in the submitted params: the sheet always belongs to the submitter" do
    victim = create(:user, :regular_user)
    user = sign_in_as(:regular)
    sign!(params: { user_id: victim.id, supervisor_names: "Evil", supervisor_contacts: "evil@example.test" })
    expect(response).to have_http_status(:created)
    expect(victim.walk_in_safety_sheets.count).to eq(0)
    sheet = user.walk_in_safety_sheets.last
    expect(sheet.supervisor_names.to_s).not_to include("Evil")
  end

  it "requires all six agreement boxes" do
    sign_in_as(:regular)
    expect { sign!(agreement: agreements.take(5)) }.not_to change(WalkInSafetySheet, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect { sign!(agreement: nil) }.not_to change(WalkInSafetySheet, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect { sign!(agreement: %w[1 1 1 1 1 0]) }.not_to change(WalkInSafetySheet, :count)
  end

  it "rejects missing adult info, minor info, and emergency contact with 422" do
    sign_in_as(:regular)
    expect { sign!(params: { participant_signature: "" }) }.not_to change(WalkInSafetySheet, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect { sign!(params: { is_minor: true }) }.not_to change(WalkInSafetySheet, :count)
    expect { sign!(params: { emergency_contact_name: "" }) }.not_to change(WalkInSafetySheet, :count)
  end

  it "accepts a minor sheet with guardian details" do
    user = sign_in_as(:regular)
    sign!(params: { is_minor: true, guardian_signature: "Parent", minor_participant_name: "Kid",
                    guardian_telephone_at_home: "1", guardian_telephone_at_work: "2" })
    expect(response).to have_http_status(:created)
    expect(user.walk_in_safety_sheets.last.is_minor).to be(true)
  end

  it "answers 400->root redirect when the sheet param is missing" do
    sign_in_as(:regular)
    post walk_in_safety_sheets_path, params: { agreement: agreements }
    expect(response).to redirect_to(root_path)
  end

  it "allows one sheet per space per user, but different users may sign the same space" do
    sign_in_as(:regular)
    sign!
    expect { sign! }.not_to change(WalkInSafetySheet, :count)
    expect(response).to have_http_status(:unprocessable_content)
    post logout_path
    sign_in_as(:regular)
    expect { sign! }.to change(WalkInSafetySheet, :count).by(1)
  end

  describe "who can view others' submissions" do
    let!(:owner) { create(:user, :regular_user) }
    let!(:sheet) do
      create(:walk_in_safety_sheet, :is_adult, user: owner, space: space,
             participant_signature: "Owner Secret Signature", emergency_contact_name: "Owner Emergency Person",
             emergency_contact_telephone: "613-000-9999")
    end

    it "never renders another user's sheet to a regular user, staff or admin (show/index render the viewer's own)" do
      %i[regular staff admin].each do |role|
        sign_in_as(role)
        [walk_in_safety_sheets_path, walk_in_safety_sheet_path(space.id),
         walk_in_safety_sheet_path(sheet.id)].each do |path|
          get path
          expect(response).to have_http_status(:ok)
          expect(response.body).not_to include("Owner Secret Signature", "Owner Emergency Person", "613-000-9999")
        end
        post logout_path
      end
    end

    it "shows the owner their own submission" do
      log_in!(owner)
      get walk_in_safety_sheet_path(space.id)
      expect(response.body).to include("Owner Emergency Person", "Signed on")
    end

    it "404s when another user tries to update someone else's sheet (staff and admin too)" do
      %i[regular staff admin].each do |role|
        sign_in_as(role)
        patch walk_in_safety_sheet_path(sheet), params: { walk_in_safety_sheet: { emergency_contact_name: "Pwned" } }
        expect(response).to have_http_status(:not_found), role.to_s
        post logout_path
      end
      expect(sheet.reload.emergency_contact_name).to eq("Owner Emergency Person")
    end

    it "lets the owner update contacts and redirects to /walk_in_safety_sheets/<space_id>" do
      log_in!(owner)
      patch walk_in_safety_sheet_path(sheet), params: { walk_in_safety_sheet: { emergency_contact_name: "New Person" } }
      expect(response).to redirect_to(walk_in_safety_sheet_path(space.id))
      expect(sheet.reload.emergency_contact_name).to eq("New Person")
    end

    # update permits only the contact fields, so a signed sheet cannot be re-pointed or flipped to minor
    it "ignores space_id, is_minor and signature changes on a signed sheet" do
      other = create(:space)
      log_in!(owner)
      patch walk_in_safety_sheet_path(sheet),
            params: { walk_in_safety_sheet: { space_id: other.id, is_minor: true, participant_signature: "Forged", emergency_contact_name: "Kept Moving" } }
      sheet.reload
      expect(sheet.space_id).to eq(space.id)
      expect(sheet.is_minor).to eq(false)
      expect(sheet.participant_signature).not_to eq("Forged")
      expect(sheet.emergency_contact_name).to eq("Kept Moving")
    end

    it "re-renders 422 when an update empties a required field" do
      log_in!(owner)
      patch walk_in_safety_sheet_path(sheet), params: { walk_in_safety_sheet: { emergency_contact_name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(sheet.reload.emergency_contact_name).to eq("Owner Emergency Person")
    end

    it "has no destroy or edit action for anybody" do
      log_in!(owner)
      get edit_walk_in_safety_sheet_path(sheet)
      expect(response).to have_http_status(:not_found)
      delete walk_in_safety_sheet_path(sheet)
      expect(response).to have_http_status(:not_found).or have_http_status(:method_not_allowed)
      expect(WalkInSafetySheet.exists?(sheet.id)).to be(true)
    end
  end
end
