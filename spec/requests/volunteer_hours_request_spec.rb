# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerHoursController (a subclass of VolunteersController, so the
# inherited `grant_access` gate applies: volunteer-program member, staff or admin).
#
# Gates: grant_access (all actions); `edit` adds owner-or-staff; the two staff
# pages add staff-only. `update`, `destroy`, `update_approval` have NO ownership
# or staff check beyond grant_access (D-V01..D-V03).
RSpec.describe "Volunteer hours (HTTP contract)", type: :request do
  let(:task) { create(:volunteer_task, title: "booth") }
  let(:owner) { create(:user, :volunteer_with_volunteer_program) }
  let(:other_volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let(:hour_params) do
    { volunteer_hour: { volunteer_task_id: task.id, date_of_task: "2024-03-01", total_time: 2.5 } }
  end

  def make_hour(user: owner, approval: nil, total_time: 3)
    create(:volunteer_hour, user: user, volunteer_task: task, approval: approval, total_time: total_time)
  end

  ALLOWED = %i[volunteer inactive staff admin].freeze
  DENIED = %i[guest regular role_only].freeze

  describe "grant_access matrix" do
    DENIED.each do |role|
      it "#{role}: index redirects to root with an alert" do
        vol_sign_in_as(role)
        get volunteer_hours_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
      end

      it "#{role}: create persists nothing and redirects to root" do
        vol_sign_in_as(role)
        expect { post volunteer_hours_path, params: hour_params }.not_to change(VolunteerHour, :count)
        expect(response).to redirect_to(root_path)
      end

      it "#{role}: update_approval and destroy are refused" do
        hour = make_hour
        vol_sign_in_as(role)
        put update_approval_volunteer_hours_path(id: hour.id, approval: true)
        expect(response).to redirect_to(root_path)
        delete volunteer_hour_path(hour)
        expect(response).to redirect_to(root_path)
        expect(hour.reload.approval).to be_nil
        expect(VolunteerHour.exists?(hour.id)).to be(true)
      end
    end

    ALLOWED.each do |role|
      it "#{role}: index renders" do
        vol_sign_in_as(role)
        get volunteer_hours_path
        expect(response).to have_http_status(:ok)
      end
    end

    it "an inactive Volunteer Program membership still grants access (volunteer? ignores `active`)" do
      vol_sign_in_as(:inactive)
      get volunteer_hours_path
      expect(response).to have_http_status(:ok)
    end

    it "role 'volunteer' without a program row is denied: access derives from the Program" do
      vol_sign_in_as(:role_only)
      get volunteer_hours_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /volunteer_hours (index)" do
    # N+1 pinned: see defects D-PERF-V01 (view calls vh.volunteer_task per row)
    it "lists only the signed-in user's hours and totals approved ones", skip_bullet: true do
      make_hour(approval: true, total_time: 2)
      make_hour(approval: true, total_time: 1.5)
      make_hour(approval: nil, total_time: 9)
      make_hour(user: other_volunteer, approval: true, total_time: 100)
      vol_login!(owner)
      get volunteer_hours_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("3.5 hours")
      expect(response.body).not_to include("100.0 Hours")
    end

    # WART(D-V09): an hour whose volunteer_task_id points at nothing (accepted on create) 500s the owner's index
    it "500s when one of the user's hours references a missing task" do
      VolunteerHour.create!(user: owner, volunteer_task_id: 999_999, total_time: 1)
      vol_login!(owner)
      get volunteer_hours_path
      expect(response).to have_http_status(:internal_server_error)
      expect(vol_error_text).to include("undefined method 'title' for nil")
    end
  end

  describe "GET /volunteer_hours/new" do
    # WART(D-V10): route exists but there is no action/template (only a partial)
    it "is a 404 for a volunteer" do
      vol_login!(owner)
      get new_volunteer_hour_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /volunteer_hours (create)" do
    before { vol_login!(owner) }

    it "persists an unprocessed hour for the current user and redirects with a notice" do
      expect { post volunteer_hours_path, params: hour_params }.to change(VolunteerHour, :count).by(1)
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:notice]).to eq("You've successfully sent your volunteer working hours")
      hour = VolunteerHour.last
      expect(hour.user_id).to eq(owner.id)
      expect(hour.volunteer_task_id).to eq(task.id)
      expect(hour.total_time).to eq(2.5)
      expect(hour.approval).to be_nil
    end

    # WART(D-V01): `approval` is permitted, so a volunteer submits hours already approved (self-approval)
    it "lets the submitter set approval: true on their own new hour" do
      post volunteer_hours_path, params: { volunteer_hour: hour_params[:volunteer_hour].merge(approval: true) }
      expect(VolunteerHour.last.approval).to be(true)
      expect(owner.get_total_hours).to eq(2.5)
    end

    # WART(D-V04): no range validation: negative and far-future hours are stored
    it "accepts negative total_time and a far-future date_of_task" do
      post volunteer_hours_path,
           params: { volunteer_hour: { volunteer_task_id: task.id, date_of_task: "2999-01-01", total_time: -5 } }
      expect(response).to redirect_to(volunteer_hours_path)
      hour = VolunteerHour.last
      expect(hour.total_time).to eq(-5)
      expect(hour.date_of_task.year).to eq(2999)
    end

    it "rounds total_time to 2 decimals (decimal(9,2))" do
      post volunteer_hours_path,
           params: { volunteer_hour: { volunteer_task_id: task.id, total_time: 1.239 } }
      expect(VolunteerHour.last.total_time).to eq(1.24)
    end

    # WART(D-V05): non-numeric total_time silently becomes 0
    it "stores 0 for a non-numeric total_time" do
      post volunteer_hours_path, params: { volunteer_hour: { volunteer_task_id: task.id, total_time: "abc" } }
      expect(response).to redirect_to(volunteer_hours_path)
      expect(VolunteerHour.last.total_time).to eq(0)
    end

    # WART(D-V06): over-range total_time raises ActiveRecord::RangeError (500) instead of a validation message
    it "500s for a total_time beyond decimal(9,2)" do
      expect do
        post volunteer_hours_path, params: { volunteer_hour: { volunteer_task_id: task.id, total_time: 99_999_999_999 } }
      end.not_to change(VolunteerHour, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(vol_error_text).to include("ActiveRecord::RangeError")
    end

    # WART(D-V07): missing volunteer_task_id hits the NOT NULL constraint (500)
    it "500s without a volunteer_task_id" do
      expect { post volunteer_hours_path, params: { volunteer_hour: { total_time: 1 } } }
        .not_to change(VolunteerHour, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(vol_error_text).to include("ActiveRecord::NotNullViolation")
    end

    # WART(D-V08): the task is never checked to exist, so an orphan hour is stored (and later breaks the index, D-V09)
    it "stores an hour for a nonexistent task id" do
      expect do
        post volunteer_hours_path, params: { volunteer_hour: { volunteer_task_id: 999_999, total_time: 1 } }
      end.to change(VolunteerHour, :count).by(1)
      expect(VolunteerHour.last.volunteer_task).to be_nil
    end

    it "does not require the user to have joined the task" do
      expect { post volunteer_hours_path, params: hour_params }.to change(VolunteerHour, :count).by(1)
      expect(owner.volunteer_task_joins).to be_empty
    end

    it "ignores a user_id param (hours always belong to the submitter)" do
      post volunteer_hours_path,
           params: { volunteer_hour: hour_params[:volunteer_hour].merge(user_id: other_volunteer.id) }
      expect(VolunteerHour.last.user_id).to eq(owner.id)
    end

    it "redirects to root with the missing-param message when volunteer_hour is absent" do
      post volunteer_hours_path, params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/param is missing/)
    end
  end

  describe "GET /volunteer_hours/:id/edit" do
    it "renders for the owner" do
      hour = make_hour(total_time: 2.5)
      vol_login!(owner)
      get edit_volunteer_hour_path(hour)
      expect(response).to have_http_status(:ok)
    end

    it "renders for staff on someone else's hour" do
      hour = make_hour
      vol_login!(create(:user, :staff))
      get edit_volunteer_hour_path(hour)
      expect(response).to have_http_status(:ok)
    end

    it "refuses another volunteer with an alert and redirect to their own list" do
      hour = make_hour
      vol_login!(other_volunteer)
      get edit_volunteer_hour_path(hour)
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:alert]).to eq("You are not authorized to edit this.")
    end

    it "404s for a missing id" do
      vol_login!(owner)
      get edit_volunteer_hour_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /volunteer_hours/:id (update)" do
    # WART(D-V02): update has no ownership check: any volunteer edits anyone's hour, even a processed one, and can set approval
    it "lets another volunteer change someone else's hour, including approval" do
      hour = make_hour(approval: false, total_time: 1)
      vol_login!(other_volunteer)
      patch volunteer_hour_path(hour), params: { volunteer_hour: { total_time: 40, approval: true } }
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:notice]).to eq("Volunteer hour updated")
      expect(hour.reload.total_time).to eq(40)
      expect(hour.approval).to be(true)
      expect(hour.user_id).to eq(owner.id)
    end

    it "redirects staff/admin to the requests page" do
      hour = make_hour
      vol_login!(create(:user, :admin))
      patch volunteer_hour_path(hour), params: { volunteer_hour: { total_time: 4 } }
      expect(response).to redirect_to(volunteer_hour_requests_volunteer_hours_path)
      expect(hour.reload.total_time).to eq(4)
    end

    # WART(D-V11): redirect is chosen by users.role, so a program member whose role is regular_user is sent to the staff-only page
    it "sends a program member with role regular_user to the staff page, which then bounces them" do
      member = create(:user, :regular_user)
      Program.create!(user: member, program_type: Program::VOLUNTEER)
      hour = make_hour(user: member)
      vol_login!(member)
      patch volunteer_hour_path(hour), params: { volunteer_hour: { total_time: 4 } }
      expect(response).to redirect_to(volunteer_hour_requests_volunteer_hours_path)
      follow_redirect!
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:alert]).to eq("You are not authorized access this area")
    end

    it "500s for an out-of-range total_time" do
      hour = make_hour
      vol_login!(owner)
      patch volunteer_hour_path(hour), params: { volunteer_hour: { total_time: 99_999_999_999 } }
      expect(response).to have_http_status(:internal_server_error)
      expect(hour.reload.total_time).to eq(3)
    end

    it "404s for a missing id" do
      vol_login!(owner)
      patch volunteer_hour_path(id: 999_999), params: { volunteer_hour: { total_time: 1 } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /volunteer_hours/:id" do
    it "lets the owner delete an unprocessed hour" do
      hour = make_hour
      vol_login!(owner)
      expect { delete volunteer_hour_path(hour) }.to change(VolunteerHour, :count).by(-1)
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:notice]).to eq("Volunteer Hour Deleted")
    end

    # WART(D-V03): no ownership check: any volunteer deletes another volunteer's unprocessed hour
    it "lets a different volunteer delete someone else's unprocessed hour" do
      hour = make_hour
      vol_login!(other_volunteer)
      expect { delete volunteer_hour_path(hour) }.to change(VolunteerHour, :count).by(-1)
      expect(flash[:notice]).to eq("Volunteer Hour Deleted")
    end

    it "refuses a volunteer deleting a processed hour" do
      hour = make_hour(approval: true)
      vol_login!(owner)
      expect { delete volunteer_hour_path(hour) }.not_to change(VolunteerHour, :count)
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:alert]).to eq("Something went wrong or this volunteer hour was processed.")
    end

    it "lets staff delete a processed hour (staff is redirected to the requests page)" do
      hour = make_hour(approval: true)
      vol_login!(create(:user, :staff))
      expect { delete volunteer_hour_path(hour) }.to change(VolunteerHour, :count).by(-1)
      expect(response).to redirect_to(volunteer_hour_requests_volunteer_hours_path)
    end

    it "404s for a missing id" do
      vol_login!(owner)
      delete volunteer_hour_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /volunteer_hours/update_approval" do
    # WART(D-V01): update_approval has no staff check: a volunteer approves any hour, including their own
    it "lets a volunteer approve their own hour" do
      hour = make_hour(total_time: 8)
      vol_login!(owner)
      put update_approval_volunteer_hours_path, params: { id: hour.id, approval: "true" }
      expect(response).to redirect_to(volunteer_hours_path)
      expect(flash[:notice]).to eq("Volunteer hour updated")
      expect(hour.reload.approval).to be(true)
      expect(owner.get_total_hours).to eq(8)
    end

    it "rejects with approval=false for staff and redirects to the requests page" do
      hour = make_hour
      vol_login!(create(:user, :staff))
      put update_approval_volunteer_hours_path, params: { id: hour.id, approval: "false" }
      expect(response).to redirect_to(volunteer_hour_requests_volunteer_hours_path)
      expect(hour.reload.approval).to be(false)
    end

    it "resets a processed hour to unprocessed when approval is blank or absent" do
      hour = make_hour(approval: true)
      vol_login!(create(:user, :admin))
      put update_approval_volunteer_hours_path, params: { id: hour.id }
      expect(hour.reload.approval).to be_nil
    end

    it "sends no email and creates no CC money" do
      hour = make_hour
      vol_login!(create(:user, :staff))
      ActionMailer::Base.deliveries.clear
      expect do
        perform_enqueued_jobs { put update_approval_volunteer_hours_path, params: { id: hour.id, approval: "true" } }
      end.not_to change(CcMoney, :count)
      expect(vol_deliveries).to be_empty
    end
  end

  describe "staff pages" do
    %i[volunteer inactive].each do |role|
      it "#{role}: volunteer_hour_requests and volunteer_hour_per_user redirect to their hours with an alert" do
        vol_sign_in_as(role)
        get volunteer_hour_requests_volunteer_hours_path
        expect(response).to redirect_to(volunteer_hours_path)
        expect(flash[:alert]).to eq("You are not authorized access this area")
        get volunteer_hour_per_user_volunteer_hours_path
        expect(response).to redirect_to(volunteer_hours_path)
      end
    end

    %i[guest regular role_only].each do |role|
      it "#{role}: staff pages redirect to root (grant_access runs first)" do
        vol_sign_in_as(role)
        get volunteer_hour_requests_volunteer_hours_path
        expect(response).to redirect_to(root_path)
      end
    end

    %i[staff admin].each do |role|
      it "#{role}: volunteer_hour_requests renders pending and processed hours" do
        make_hour(approval: nil)
        make_hour(approval: true)
        vol_sign_in_as(role)
        get volunteer_hour_requests_volunteer_hours_path
        expect(response).to have_http_status(:ok)
      end

      it "#{role}: volunteer_hour_per_user renders per-volunteer totals" do
        make_hour(approval: true)
        make_hour(user: other_volunteer, approval: false)
        vol_sign_in_as(role)
        get volunteer_hour_per_user_volunteer_hours_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
