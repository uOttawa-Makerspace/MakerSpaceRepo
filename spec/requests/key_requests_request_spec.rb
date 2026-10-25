require "rails_helper"

# Chunk 15: KeyRequestsController (wizard staff / Teams members fill in to
# request a physical key). Gate `ensure_staff_or_teams_program`: staff, admin
# or Teams-program members; guests and everyone else go to root with
# "You cannot access this area.". The wizard is an in-place status machine:
# in_progress -> (step 6) waiting_for_approval -> (admin) approved.
RSpec.describe "Key requests", type: :request do
  let!(:space) { create(:space) }
  let!(:supervisor) { create(:user, :admin) }
  let(:valid_attrs) do
    {
      student_number: "300123456",
      phone_number: "613-555-1234",
      emergency_contact: "Jane Doe",
      emergency_contact_relation: "Mother",
      emergency_contact_phone_number: "613-555-9876",
      space_id: space.id,
      user_status: "student",
      supervisor_id: supervisor.id
    }
  end
  let(:answers) { (1..KeyRequest::NUMBER_OF_QUESTIONS).to_h { |i| ["question_#{i}", "answer #{i}"] } }

  def teams_member
    create(:user, :regular_user).tap { |u| Program.create!(user: u, program_type: Program::TEAMS) }
  end

  describe "auth matrix" do
    paths = {
      index: -> { get key_requests_path },
      new: -> { get new_key_request_path },
      create: -> { post key_requests_path, params: { key_request: { student_number: "1" } } },
      show: -> { get key_request_path(1) },
      steps: -> { get key_request_steps_path(1, step: 1) }
    }
    paths.each do |name, call|
      %i[guest regular volunteer].each do |role|
        it "#{name}: bounces a #{role} to root" do
          sign_in_as(role)
          instance_exec(&call)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("You cannot access this area.")
        end
      end
    end

    it "does not persist a request created by a guest or regular user" do
      expect { post key_requests_path, params: { key_request: valid_attrs } }.not_to change(KeyRequest, :count)
      sign_in_as(:regular)
      expect { post key_requests_path, params: { key_request: valid_attrs } }.not_to change(KeyRequest, :count)
    end

    it "admits a Teams-program member" do
      log_in!(teams_member)
      get new_key_request_path
      expect(response).to have_http_status(:ok)
    end

    it "admits an admin" do
      sign_in_as(:admin)
      get new_key_request_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "index routing" do
    let!(:staff) { sign_in_as(:staff) }

    it "sends a user without a request to the new form" do
      get key_requests_path
      expect(response).to redirect_to(new_key_request_path)
    end

    it "sends in-progress requests to step 1 and others to the show page" do
      kr = create(:key_request, :status_in_progress, user: staff, supervisor: supervisor, space: space)
      get key_requests_path
      expect(response).to redirect_to(key_request_steps_path(key_request_id: kr.id, step: 1))
      kr.update_columns(status: KeyRequest.statuses[:waiting_for_approval])
      get key_requests_path
      expect(response).to redirect_to(key_request_path(kr.id))
    end
  end

  describe "POST create" do
    let!(:staff) { sign_in_as(:staff) }

    it "creates an in_progress request for the current user and goes to step 2" do
      expect { post key_requests_path, params: { key_request: valid_attrs } }.to change(KeyRequest, :count).by(1)
      kr = KeyRequest.last
      expect(response).to redirect_to(key_request_steps_path(key_request_id: kr.id, step: 2))
      expect(kr).to have_attributes(user_id: staff.id, status: "in_progress", space_id: space.id, supervisor_id: supervisor.id)
    end

    it "forces user and status regardless of submitted values" do
      post key_requests_path, params: { key_request: valid_attrs.merge(status: "approved", user_id: supervisor.id) }
      expect(KeyRequest.last).to have_attributes(user_id: staff.id, status: "in_progress")
    end

    it "re-renders new with an alert on invalid data (status 200)" do
      expect { post key_requests_path, params: { key_request: valid_attrs.merge(phone_number: "abc") } }.not_to change(KeyRequest, :count)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to eq("Something went wrong while trying to submit the form.")
    end

    it "refuses a second request with a notice" do
      create(:key_request, :status_in_progress, user: staff, supervisor: supervisor, space: space)
      expect { post key_requests_path, params: { key_request: valid_attrs } }.not_to change(KeyRequest, :count)
      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(flash[:notice]).to eq("You already have a key request. You can edit your current key request.")
      get new_key_request_path
      expect(response).to redirect_to(staff_dashboard_index_path)
    end
  end

  describe "wizard steps" do
    let!(:staff) { sign_in_as(:staff) }
    let!(:kr) { create(:key_request, :status_in_progress, user: staff, supervisor: supervisor, space: space) }

    it "renders each step view" do
      (1..5).each do |step|
        get key_request_steps_path(key_request_id: kr.id, step: step)
        expect(response).to have_http_status(:ok)
      end
    end

    it "defaults to step 1 without a step param" do
      get key_request_steps_path(key_request_id: kr.id)
      expect(response).to have_http_status(:ok)
    end

    it "saves acknowledgements, coercing the string true to booleans" do
      kr.update_columns(read_lab_rules: false, read_policies: false, read_agreement: false)
      patch key_request_steps_path(key_request_id: kr.id, step: 3), params: { key_request: { read_lab_rules: "true" } }
      expect(response).to have_http_status(:ok)
      expect(kr.reload.read_lab_rules).to be true
    end

    it "saves safety-questionnaire answers while in progress" do
      patch key_request_steps_path(key_request_id: kr.id, step: 4), params: { key_request: { question_1: "911" } }
      expect(kr.reload.question_1).to eq("911")
    end

    it "redirects back one step with an alert when the update is invalid" do
      patch key_request_steps_path(key_request_id: kr.id, step: 3), params: { key_request: { phone_number: "bad" } }
      expect(response).to redirect_to(key_request_steps_path(key_request_id: kr.id, step: 2))
      expect(flash[:alert]).to eq("An error occured while saving the key request at step 3: Failed to update key request")
    end

    it "redirects an out-of-range step back to step 1" do
      get key_request_steps_path(key_request_id: kr.id, step: 9)
      expect(response).to redirect_to(key_request_steps_path(key_request_id: kr.id, step: 1))
      expect(flash[:alert]).to eq("Invalid step number")
    end

    it "does not submit step 6 until every question is answered" do
      get key_request_steps_path(key_request_id: kr.id, step: 6)
      expect(response).to redirect_to(key_request_steps_path(key_request_id: kr.id, step: 1))
      expect(flash[:alert]).to eq("There was an error when submitting your key request form. Please make sure you fill in all the required fields.")
      expect(kr.reload.status).to eq("in_progress")
    end

    it "submits at step 6 once complete, moving to waiting_for_approval" do
      kr.update!(answers.merge(read_lab_rules: true, read_policies: true, read_agreement: true))
      get key_request_steps_path(key_request_id: kr.id, step: 6)
      expect(response).to redirect_to(key_request_path(kr.id))
      expect(flash[:notice]).to start_with("You have successfully submitted the key request form")
      expect(kr.reload.status).to eq("waiting_for_approval")
    end

    # WART(D-EQ23): steps permits :status, so the requester can PATCH status=approved and approve their own key request without an admin
    it "lets the owner self-approve by sending status=approved with a complete form" do
      kr.update!(answers.merge(read_lab_rules: true, read_policies: true, read_agreement: true))
      patch key_request_steps_path(key_request_id: kr.id, step: 5), params: { key_request: { status: "approved" } }
      expect(response).to have_http_status(:ok)
      expect(kr.reload.status).to eq("approved")
    end

    it "cannot change the owner through steps" do
      patch key_request_steps_path(key_request_id: kr.id, step: 1), params: { key_request: { user_id: supervisor.id, phone_number: "613-555-0000" } }
      expect(kr.reload).to have_attributes(user_id: staff.id, phone_number: "613-555-0000")
    end

    it "redirects non-owners (even admins) away from another user's wizard" do
      sign_in_as(:admin)
      patch key_request_steps_path(key_request_id: kr.id, step: 1), params: { key_request: { phone_number: "613-555-1111" } }
      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(flash[:alert]).to eq("You don't have the permission to edit this key request.")
      expect(kr.reload.phone_number).not_to eq("613-555-1111")
    end

    it "redirects an unknown key request with an alert" do
      get key_request_steps_path(key_request_id: 0, step: 1)
      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(flash[:alert]).to eq("Key was not found.")
    end
  end

  describe "GET show" do
    let!(:owner) { create(:user, :staff) }
    let!(:kr) { create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: owner, supervisor: supervisor, space: space) }

    it "renders for the owner" do
      log_in!(owner)
      get key_request_path(kr)
      expect(response).to have_http_status(:ok)
    end

    it "renders for an admin" do
      sign_in_as(:admin)
      get key_request_path(kr)
      expect(response).to have_http_status(:ok)
    end

    it "redirects another staff member to the dashboard with an alert" do
      sign_in_as(:staff)
      get key_request_path(kr)
      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(flash[:alert]).to eq("You don't have the permissions to view this")
    end

    it "redirects an unknown id with an alert" do
      sign_in_as(:staff)
      get key_request_path(0)
      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(flash[:alert]).to eq("Key was not found.")
    end
  end
end
