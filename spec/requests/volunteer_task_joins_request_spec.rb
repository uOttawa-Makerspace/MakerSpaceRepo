# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerTaskJoinsController. It inherits only SessionsController:
# `create` needs sign-in plus staff or volunteer-program membership; `remove` needs sign-in plus owner or staff.
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

    # no uniqueness on (user, task): the same volunteer joins repeatedly when capacity allows
    it "allows the same volunteer to join twice on a multi-seat task, with two rounds of email" do
      big = create(:volunteer_task, joins: 3)
      vol_login!(volunteer)
      expect { 2.times { join!(join_params(task_id: big.id)) } }.to change(VolunteerTaskJoin, :count).by(2)
      expect(vol_deliveries.size).to eq(4)
    end

    # capacity only counts user_type "Volunteer" (users.role), so a program member whose role is regular_user is stored as "Regular_user" and never consumes a seat
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

    it "refuses a regular user with no volunteer program" do
      vol_login!(create(:user, :regular_user))
      expect { join!(join_params) }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
      expect(vol_deliveries).to be_empty
    end

    it "ignores a user_id param from a non-staff user" do
      vol_login!(volunteer)
      join!(join_params(user_id: other_volunteer.id))
      expect(VolunteerTaskJoin.last.user_id).to eq(volunteer.id)
    end

    it "lets staff join another user, regardless of capacity" do
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

    it "redirects a guest to login, nothing persisted" do
      expect { join!(join_params) }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to redirect_to(login_path)
      expect(vol_deliveries).to be_empty
    end

    it "redirects a guest to login even when the task is full" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      join!(join_params)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "notification recipient" do
    it "ignores staff whose join was removed" do
      gone = create(:user, :staff)
      current = create(:user, :staff)
      create(:volunteer_task_join, volunteer_task: task, user: current, user_type: "Staff")
      create(:volunteer_task_join, :not_active, volunteer_task: task, user: gone, user_type: "Staff")
      vol_login!(volunteer)
      join!(join_params)
      expect(vol_deliveries.map(&:to)).to contain_exactly([current.email], [volunteer.email])
    end
  end

  describe "POST /volunteer_task_joins/remove" do
    let!(:join) { create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer) }
    let(:remove_params) { { volunteer_task_join: { user_id: volunteer.id, volunteer_task_id: task.id } } }

    it "lets the volunteer leave: marks the join inactive, notice, redirect back, no email" do
      vol_login!(volunteer)
      expect do
        perform_enqueued_jobs { post remove_volunteer_task_joins_path, params: remove_params, headers: { "HTTP_REFERER" => volunteer_task_url(task) } }
      end.not_to change(VolunteerTaskJoin, :count)
      expect(join.reload.active).to be(false)
      expect(response).to redirect_to(volunteer_task_url(task))
      expect(flash[:notice]).to eq("User was removed from the Volunteer Task")
      expect(vol_deliveries).to be_empty
    end

    it "frees the seat for another volunteer" do
      vol_login!(volunteer)
      post remove_volunteer_task_joins_path, params: remove_params
      vol_login!(other_volunteer)
      post volunteer_task_joins_path, params: join_params
      expect(task.volunteer_task_joins.active.pluck(:user_id)).to eq([other_volunteer.id])
      expect(task.volunteer_task_joins.pluck(:user_id)).to contain_exactly(volunteer.id, other_volunteer.id)
    end

    # remove needs sign-in, and the target must be the caller or the caller must be staff
    it "refuses another volunteer removing someone else" do
      vol_login!(other_volunteer)
      expect { post remove_volunteer_task_joins_path, params: remove_params }.not_to change(VolunteerTaskJoin, :count)
      expect(flash[:alert]).to eq("You are not authorized to remove this user from the task.")
    end

    it "refuses a regular user removing someone else" do
      vol_login!(create(:user, :regular_user))
      expect { post remove_volunteer_task_joins_path, params: remove_params }.not_to change(VolunteerTaskJoin, :count)
    end

    it "redirects a guest to login and removes nothing" do
      expect { post remove_volunteer_task_joins_path, params: remove_params }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to redirect_to(login_path)
    end

    it "lets staff remove anyone" do
      vol_login!(create(:user, :staff))
      expect { post remove_volunteer_task_joins_path, params: remove_params }.to change { join.reload.active }.to(false)
      expect(flash[:notice]).to eq("User was removed from the Volunteer Task")
    end

    it "lets an admin remove anyone" do
      vol_login!(create(:user, :admin))
      expect { post remove_volunteer_task_joins_path, params: remove_params }.to change { join.reload.active }.to(false)
    end

    it "marks every active join of the user inactive and leaves other rows alone" do
      second = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      old = create(:volunteer_task_join, :not_active, volunteer_task: task, user: volunteer)
      other = create(:volunteer_task_join, :active, volunteer_task: task, user: other_volunteer)
      vol_login!(volunteer)
      expect { post remove_volunteer_task_joins_path, params: remove_params }.not_to change(VolunteerTaskJoin, :count)
      expect([join, second, old, other].map { |j| j.reload.active }).to eq([false, false, false, true])
    end

    it "refuses a user with no active join and changes nothing" do
      join.update!(active: false)
      vol_login!(volunteer)
      expect { post remove_volunteer_task_joins_path, params: remove_params }.not_to change { join.reload.updated_at }
      expect(flash[:alert]).to eq("The user to remove is not on this task.")
      expect(flash[:notice]).to be_nil
    end

    it "refuses removing the creator when nobody else is joined, and hands the task over once someone is" do
      creator = create(:user, :staff)
      task.update!(user: creator)
      join.update!(active: false)
      creator_join = create(:volunteer_task_join, :active_not_volunteer, volunteer_task: task, user: creator)
      vol_login!(creator)
      params = { volunteer_task_join: { user_id: creator.id, volunteer_task_id: task.id } }
      post remove_volunteer_task_joins_path, params: params
      expect(flash[:alert]).to eq("There must be at least one staff member assigned to this task.")
      expect([creator_join.reload.active, task.reload.user_id]).to eq([true, creator.id])

      join.update!(active: true)
      post remove_volunteer_task_joins_path, params: params
      expect([creator_join.reload.active, task.reload.user_id]).to eq([false, volunteer.id])
    end

    it "redirects with the missing-param alert instead of a 500 when the volunteer_task_join param is missing" do
      vol_login!(volunteer)
      expect { post remove_volunteer_task_joins_path }.not_to change(VolunteerTaskJoin, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("volunteer_task_join")
    end

    it "redirects with the missing-param alert when volunteer_task_join is a plain string" do
      vol_login!(volunteer)
      expect { post remove_volunteer_task_joins_path, params: { volunteer_task_join: "x" } }
        .not_to change(VolunteerTaskJoin, :count)
      expect(response).to redirect_to(root_path)
    end

    it "refuses a user who never joined the task, with a message" do
      vol_login!(other_volunteer)
      post remove_volunteer_task_joins_path,
           params: { volunteer_task_join: { user_id: other_volunteer.id, volunteer_task_id: task.id } }
      expect(flash[:alert]).to eq("The user to remove is not on this task.")
    end

    it "404s when the task does not exist" do
      vol_login!(other_volunteer)
      post remove_volunteer_task_joins_path,
           params: { volunteer_task_join: { user_id: other_volunteer.id, volunteer_task_id: 999_999 } }
      expect(response).to have_http_status(:not_found)
    end
  end
end
