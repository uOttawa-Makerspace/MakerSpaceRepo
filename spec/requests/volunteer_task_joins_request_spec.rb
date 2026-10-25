# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerTaskJoinsController. It inherits only SessionsController:
# NO sign-in, role or ownership gate on either action.
RSpec.describe "Volunteer task joins (HTTP contract)", type: :request do
  let(:task) { create(:volunteer_task, title: "open house", joins: 1) }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let(:other_volunteer) { create(:user, :volunteer_with_volunteer_program) }

  before { ActionMailer::Base.deliveries.clear }

  def join_params(user_id: nil, task_id: task.id)
    { volunteer_task_join: { volunteer_task_id: task_id, user_id: user_id }.compact }
  end

  def join!(params, headers: {})
    perform_enqueued_jobs { post volunteer_task_joins_path, params: params, headers: headers }
  end

  describe "POST /volunteer_task_joins (join)" do
    it "joins a volunteer, redirects back with a notice and sends two emails" do
      vol_login!(volunteer)
      expect { join!(join_params, headers: { "HTTP_REFERER" => volunteer_task_url(task) }) }
        .to change(VolunteerTaskJoin, :count).by(1)
      expect(response).to redirect_to(volunteer_task_url(task))
      expect(flash[:notice]).to eq("An user was successfully joined to this volunteer task.")
      row = VolunteerTaskJoin.last
      expect([row.user_id, row.volunteer_task_id, row.user_type, row.active]).to eq([volunteer.id, task.id, "Volunteer", true])

      expect(vol_deliveries.map { |m| [m.to, m.subject] }).to contain_exactly(
        [["volunteer@makerepo.com"], "New join in task: Open house"],
        [[volunteer.email], "New join in task: Open house"]
      )
    end

    it "notifies the last Staff/Admin joined to the task instead of the fallback address" do
      staff = create(:user, :staff)
      create(:volunteer_task_join, volunteer_task: task, user: staff, user_type: "Staff")
      vol_login!(volunteer)
      join!(join_params)
      expect(vol_deliveries.map(&:to)).to contain_exactly([staff.email], [volunteer.email])
    end

    it "falls back to the root path without a Referer" do
      vol_login!(volunteer)
      join!(join_params)
      expect(response).to redirect_to(root_path)
    end

    it "refuses a second volunteer once the task is full (counts active Volunteer joins)" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      vol_login!(volunteer)
      expect { join!(join_params) }.not_to change(VolunteerTaskJoin, :count)
      expect(flash[:alert]).to eq("This task is already full")
      expect(vol_deliveries).to be_empty
    end

    it "does not count inactive joins toward capacity" do
      create(:volunteer_task_join, :not_active, volunteer_task: task)
      vol_login!(volunteer)
      expect { join!(join_params) }.to change(VolunteerTaskJoin, :count).by(1)
    end

    it "does not count Staff/Admin joins toward capacity" do
      create(:volunteer_task_join, :active_not_volunteer, volunteer_task: task)
      vol_login!(volunteer)
      expect { join!(join_params) }.to change(VolunteerTaskJoin, :count).by(1)
    end

    # WART(D-V12): no uniqueness on (user, task): the same volunteer joins repeatedly when capacity allows
    it "allows the same volunteer to join twice on a multi-seat task, with two rounds of email" do
      big = create(:volunteer_task, joins: 3)
      vol_login!(volunteer)
      expect { 2.times { join!(join_params(task_id: big.id)) } }.to change(VolunteerTaskJoin, :count).by(2)
      expect(vol_deliveries.size).to eq(4)
    end

    # WART(D-V13): capacity only counts user_type "Volunteer" (users.role), so a program member whose role is regular_user is stored as "Regular_user" and never consumes a seat
    it "stores a program member with role regular_user as Regular_user, leaving the seat free for others" do
      member = create(:user, :regular_user)
      Program.create!(user: member, program_type: Program::VOLUNTEER)
      vol_login!(member)
      expect { join!(join_params) }.to change(VolunteerTaskJoin, :count).by(1)
      expect(VolunteerTaskJoin.last.user_type).to eq("Regular_user")
      expect(task.volunteer_task_joins.active.user_type_volunteer.count).to eq(0)
      post login_authentication_path, params: { username_email: volunteer.username, password: VolunteerSpecHelpers::VOLUNTEER_PASSWORD }
      expect { join!(join_params) }.to change(VolunteerTaskJoin, :count).by(1)
      expect(task.volunteer_task_joins.count).to eq(2)
    end

    it "blocks that same member when the task is already full of Volunteer joins" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      member = create(:user, :regular_user)
      Program.create!(user: member, program_type: Program::VOLUNTEER)
      vol_login!(member)
      expect { join!(join_params) }.not_to change(VolunteerTaskJoin, :count)
      expect(flash[:alert]).to eq("This task is already full")
    end

    # WART(D-V14): no role gate: a plain regular user (no program) joins any task
    it "lets a regular user with no program join" do
      user = create(:user, :regular_user)
      vol_login!(user)
      expect { join!(join_params) }.to change(VolunteerTaskJoin, :count).by(1)
      expect(VolunteerTaskJoin.last.user_id).to eq(user.id)
    end

    it "ignores a user_id param from a non-staff user" do
      vol_login!(volunteer)
      join!(join_params(user_id: other_volunteer.id))
      expect(VolunteerTaskJoin.last.user_id).to eq(volunteer.id)
    end

    it "lets staff join another user, bypassing capacity" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      staff = create(:user, :staff)
      vol_login!(staff)
      expect { join!(join_params(user_id: volunteer.id)) }.to change(VolunteerTaskJoin, :count).by(1)
      expect(VolunteerTaskJoin.last.user_id).to eq(volunteer.id.to_s.to_i)
      expect(VolunteerTaskJoin.last.user_type).to eq("Volunteer")
    end

    it "joins staff to themselves when no user_id is given, typed Staff" do
      staff = create(:user, :staff)
      vol_login!(staff)
      join!(join_params)
      expect(VolunteerTaskJoin.last.attributes.values_at("user_id", "user_type")).to eq([staff.id, "Staff"])
    end

    it "500s when staff names a nonexistent user" do
      vol_login!(create(:user, :staff))
      expect { join!(join_params(user_id: 999_999)) }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to have_http_status(:internal_server_error)
    end

    it "500s for a nonexistent task" do
      vol_login!(volunteer)
      join!(join_params(task_id: 999_999))
      expect(response).to have_http_status(:internal_server_error)
    end

    it "redirects to root with the missing-param message when the key is absent" do
      vol_login!(volunteer)
      post volunteer_task_joins_path, params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/param is missing/)
    end

    it "guest on a task with free capacity: 500 (current_user.id is nil), nothing persisted" do
      expect { join!(join_params) }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to have_http_status(:internal_server_error)
      expect(vol_deliveries).to be_empty
    end

    it "guest on a full task gets the 'already full' flash and a redirect" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      join!(join_params)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("This task is already full")
    end
  end

  describe "POST /volunteer_task_joins/remove" do
    let!(:join) { create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer) }
    let(:remove_params) { { volunteer_task_join: { user_id: volunteer.id, volunteer_task_id: task.id } } }

    it "lets the volunteer leave: destroys the join, notice, redirect back, no email" do
      vol_login!(volunteer)
      expect do
        perform_enqueued_jobs { post remove_volunteer_task_joins_path, params: remove_params, headers: { "HTTP_REFERER" => volunteer_task_url(task) } }
      end.to change(VolunteerTaskJoin, :count).by(-1)
      expect(response).to redirect_to(volunteer_task_url(task))
      expect(flash[:notice]).to eq("User was removed from the Volunteer Task")
      expect(vol_deliveries).to be_empty
    end

    it "frees the seat for another volunteer" do
      vol_login!(other_volunteer)
      post remove_volunteer_task_joins_path, params: remove_params
      post volunteer_task_joins_path, params: join_params
      expect(task.volunteer_task_joins.pluck(:user_id)).to eq([other_volunteer.id])
    end

    # WART(D-V15): remove has no auth/ownership check: any volunteer removes anyone, and a GUEST can too (unauthenticated write)
    it "lets another volunteer remove someone else" do
      vol_login!(other_volunteer)
      expect { post remove_volunteer_task_joins_path, params: remove_params }.to change(VolunteerTaskJoin, :count).by(-1)
    end

    it "lets a guest remove a volunteer from a task" do
      expect { post remove_volunteer_task_joins_path, params: remove_params }.to change(VolunteerTaskJoin, :count).by(-1)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("User was removed from the Volunteer Task")
    end

    it "destroys only one join when duplicates exist" do
      create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      expect { post remove_volunteer_task_joins_path, params: remove_params }.to change(VolunteerTaskJoin, :count).by(-1)
    end

    it "500s when no such join exists" do
      post remove_volunteer_task_joins_path,
           params: { volunteer_task_join: { user_id: other_volunteer.id, volunteer_task_id: task.id } }
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
