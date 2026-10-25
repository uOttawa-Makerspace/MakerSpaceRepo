# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerTasksController.
#   index, show         staff or volunteer-program member (`volunteer_access`)
#   new/create/edit/update/destroy   staff or admin only (`grant_access`)
#   my_tasks, complete_task          NO gate (guests included)
RSpec.describe "Volunteer tasks (HTTP contract)", type: :request do
  let(:space) { create(:space) }
  let(:staff) { create(:user, :staff) }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:task) { create(:volunteer_task, title: "Setup crew", space: space, joins: 2, cc: 7, hours: 2) }

  def ivar(name)
    controller.instance_variable_get(name)
  end

  def task_params(overrides = {})
    { volunteer_task: { title: "New task", description: "d", space_id: space.id, joins: 3, category: "Events", cc: 5, hours: 1.5 }.merge(overrides) }
  end

  describe "index and show gate" do
    %i[guest regular role_only].each do |role|
      it "#{role}: index and show redirect to root with an alert" do
        vol_sign_in_as(role)
        get volunteer_tasks_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
        get volunteer_task_path(task)
        expect(response).to redirect_to(root_path)
      end
    end

    %i[volunteer inactive staff admin].each do |role|
      it "#{role}: index and show render" do
        vol_sign_in_as(role)
        get volunteer_tasks_path
        expect(response).to have_http_status(:ok)
        get volunteer_task_path(task)
        expect(response).to have_http_status(:ok)
      end
    end

    it "404s for a missing task" do
      vol_login!(volunteer)
      get volunteer_task_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /volunteer_tasks (index partitions)" do
    it "splits open tasks by active Volunteer joins, plus completed tasks" do
      assigned = create(:volunteer_task, title: "assigned")
      create(:volunteer_task_join, :active, volunteer_task: assigned)
      freed = create(:volunteer_task, title: "freed")
      create(:volunteer_task_join, :not_active, volunteer_task: freed)
      staff_only = create(:volunteer_task, title: "staffonly")
      create(:volunteer_task_join, :active_not_volunteer, volunteer_task: staff_only)
      done = create(:volunteer_task, title: "done", status: "completed")
      vol_login!(volunteer)
      get volunteer_tasks_path
      expect(ivar(:@available_volunteer_tasks)).to contain_exactly(task, freed, staff_only)
      expect(ivar(:@assigned_volunteer_tasks)).to contain_exactly(assigned)
      expect(ivar(:@completed_volunteer_tasks)).to contain_exactly(done)
    end
  end

  describe "show for staff" do
    it "lists joinable volunteers/staff and those already in the task" do
      joined = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      free_volunteer = create(:user, :volunteer_with_volunteer_program)
      vol_login!(staff)
      get volunteer_task_path(task)
      expect(ivar(:@volunteers_in_task).map(&:last)).to eq([joined.user_id])
      expect(ivar(:@volunteers).map(&:last)).to include(free_volunteer.id)
      expect(ivar(:@volunteers).map(&:last)).not_to include(joined.user_id)
      expect(ivar(:@staff).map(&:last)).to include(staff.id)
    end

    it "shows a volunteer their own pending request for the task" do
      req = create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task)
      create(:volunteer_task_request, :approved, user: volunteer, volunteer_task: task)
      vol_login!(volunteer)
      get volunteer_task_path(task)
      expect(ivar(:@volunteer_task_request)).to eq(req)
      expect(ivar(:@volunteers)).to be_nil
    end
  end

  describe "staff-only actions: role matrix" do
    %i[guest regular role_only volunteer inactive].each do |role|
      it "#{role}: new/create/edit/update/destroy redirect to root with an alert and change nothing" do
        vol_sign_in_as(role)
        get new_volunteer_task_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
        expect { post volunteer_tasks_path, params: task_params }.not_to change(VolunteerTask, :count)
        expect(response).to redirect_to(root_path)
        get edit_volunteer_task_path(task)
        expect(response).to redirect_to(root_path)
        patch volunteer_task_path(task), params: task_params(title: "hacked")
        expect(response).to redirect_to(root_path)
        expect(task.reload.title).to eq("Setup crew")
        expect { delete volunteer_task_path(task) }.not_to change(VolunteerTask, :count)
        expect(response).to redirect_to(root_path)
      end
    end

    %i[staff admin].each do |role|
      it "#{role}: new and edit render" do
        vol_sign_in_as(role)
        get new_volunteer_task_path
        expect(response).to have_http_status(:ok)
        get edit_volunteer_task_path(task)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /volunteer_tasks (create)" do
    before { vol_login!(staff) }

    it "creates the task owned by the staff user, redirects with a notice" do
      expect { post volunteer_tasks_path, params: task_params }.to change(VolunteerTask, :count).by(1)
      expect(response).to redirect_to(volunteer_tasks_path)
      expect(flash[:notice]).to eq("You've successfully created a new Volunteer Task")
      created = VolunteerTask.last
      expect(created.attributes.values_at("title", "user_id", "space_id", "joins", "category", "cc", "status"))
        .to eq(["New task", staff.id, space.id, 3, "Events", 5, "open"])
      expect(created.hours).to eq(1.5)
    end

    it "creates required trainings from certifications_id" do
      trainings = create_list(:training, 2)
      post volunteer_tasks_path, params: task_params.merge(certifications_id: trainings.map(&:id))
      expect(VolunteerTask.last.require_trainings.pluck(:training_id)).to match_array(trainings.map(&:id))
    end

    it "joins listed staff (typed by role) and volunteers (typed Volunteer, active)" do
      other_staff = create(:user, :admin)
      post volunteer_tasks_path, params: task_params.merge(staff_id: other_staff.id, volunteer_id: [volunteer.id])
      joins = VolunteerTask.last.volunteer_task_joins.order(:id)
      expect(joins.map { |j| [j.user_id, j.user_type, j.active] })
        .to eq([[other_staff.id, "Admin", true], [volunteer.id, "Volunteer", true]])
    end

    # WART(D-V20): no validation on numbers/status/title: negative cc/hours, zero seats, blank title and arbitrary status are stored
    it "stores negative cc/hours, zero seats, an empty title and a bogus status" do
      post volunteer_tasks_path, params: task_params(title: "", cc: -50, hours: -3, joins: 0, status: "bogus")
      expect(response).to redirect_to(volunteer_tasks_path)
      created = VolunteerTask.last
      expect(created.attributes.values_at("title", "cc", "joins", "status")).to eq(["", -50, 0, "bogus"])
      expect(created.hours).to eq(-3)
    end

    it "redirects to root with the missing-param message when volunteer_task is absent" do
      post volunteer_tasks_path, params: {}
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to match(/param is missing/)
    end

    it "attaches an uploaded image as a Photo (max 5 taken)" do
      img = Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets/avatar.png"), "image/png")
      expect { post volunteer_tasks_path, params: task_params.merge(images: [img]) }.to change(Photo, :count).by(1)
      expect(VolunteerTask.last.photos.count).to eq(1)
    end
  end

  describe "PATCH /volunteer_tasks/:id (update)" do
    before { vol_login!(staff) }

    it "updates attributes, redirects to the list with a notice" do
      patch volunteer_task_path(task), params: task_params(title: "Renamed", cc: 99)
      expect(response).to redirect_to(volunteer_tasks_path)
      expect(flash[:notice]).to eq("Volunteer task updated")
      expect(task.reload.attributes.values_at("title", "cc")).to eq(["Renamed", 99])
    end

    it "replaces required trainings, and clears them when certifications_id is absent" do
      old = create(:training)
      task.create_certifications([old.id])
      fresh = create(:training)
      patch volunteer_task_path(task), params: task_params.merge(certifications_id: [fresh.id])
      expect(task.require_trainings.reload.pluck(:training_id)).to eq([fresh.id])
      patch volunteer_task_path(task), params: task_params
      expect(task.require_trainings.reload).to be_empty
    end

    it "adds and removes joins" do
      keep = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      gone = create(:volunteer_task_join, :active, volunteer_task: task)
      new_volunteer = create(:user, :volunteer_with_volunteer_program)
      patch volunteer_task_path(task),
            params: task_params.merge(volunteer_id: [new_volunteer.id], remove_volunteer_id: [gone.user_id])
      expect(task.volunteer_task_joins.pluck(:user_id)).to contain_exactly(keep.user_id, new_volunteer.id)
    end

    it "flashes an error (but still updates) when a removal target is not joined" do
      patch volunteer_task_path(task), params: task_params(title: "x").merge(remove_volunteer_id: [volunteer.id])
      expect(response).to redirect_to(volunteer_tasks_path)
      expect(flash[:error]).to eq("The volunteer could not be deleted from this task, please try again later.")
      expect(task.reload.title).to eq("x")
    end

    # WART(D-V21): removing the creating staff member when nobody else is joined redirects twice (DoubleRenderError 500); the update itself IS applied
    it "500s with DoubleRenderError when removing the task creator with no other join" do
      task.update!(user_id: staff.id)
      create(:volunteer_task_join, :first, volunteer_task: task, user: staff, user_type: "Staff")
      patch volunteer_task_path(task), params: task_params(title: "never").merge(remove_staff_id: [staff.id])
      expect(response).to have_http_status(:internal_server_error)
      expect(vol_error_text).to include("DoubleRenderError")
      expect(task.reload.title).to eq("never")
      expect(flash[:error]).to eq("There must be at least one staff member assigned to this task.")
    end

    it "hands the task to another joined user when the creator is removed" do
      other = create(:user, :admin)
      task.update!(user_id: staff.id)
      create(:volunteer_task_join, volunteer_task: task, user: staff, user_type: "Staff")
      create(:volunteer_task_join, volunteer_task: task, user: other, user_type: "Admin")
      patch volunteer_task_path(task), params: task_params.merge(remove_staff_id: [staff.id])
      expect(response).to redirect_to(volunteer_tasks_path)
      expect(task.reload.user_id).to eq(other.id)
      expect(task.volunteer_task_joins.pluck(:user_id)).to eq([other.id])
    end

    it "404s for a missing task" do
      patch volunteer_task_path(id: 999_999), params: task_params
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /volunteer_tasks/:id" do
    before { vol_login!(staff) }

    it "destroys the task, its required trainings, joins, requests, hours and CC money" do
      task.create_certifications([create(:training).id])
      create(:volunteer_task_join, :active, volunteer_task: task)
      create(:volunteer_task_request, :approved, volunteer_task: task)
      create(:volunteer_hour, :approved1, volunteer_task: task)
      create(:cc_money, volunteer_task: task)
      expect { delete volunteer_task_path(task) }.to change(VolunteerTask, :count).by(-1)
      expect(response).to redirect_to(volunteer_tasks_path)
      expect(flash[:notice]).to eq("Volunteer Task Deleted")
      expect([RequireTraining, VolunteerTaskJoin, VolunteerTaskRequest, VolunteerHour, CcMoney].map { |m| m.where(volunteer_task_id: task.id).count })
        .to eq([0, 0, 0, 0, 0])
    end

    # WART(D-V22): deleting a task destroys approved hours and CC money already awarded, and the wallet is not recomputed
    it "wipes awarded hours and leaves a stale wallet" do
      awardee = create(:user, :volunteer_with_volunteer_program)
      create(:volunteer_hour, :approved1, user: awardee, volunteer_task: task)
      create(:cc_money, user: awardee, volunteer_task: task, cc: 40)
      awardee.update_wallet
      expect(awardee.reload.wallet).to eq(40)
      delete volunteer_task_path(task)
      expect(awardee.get_total_hours).to eq(0)
      expect(awardee.get_total_cc).to eq(0)
      expect(awardee.reload.wallet).to eq(40)
    end

    it "404s for a missing task" do
      delete volunteer_task_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /volunteer_tasks/complete_task" do
    # WART(D-V23): state-changing GET with no gate: a guest marks any task completed
    it "completes the task for a guest and redirects to my_tasks, with no flash" do
      get complete_task_volunteer_tasks_path(id: task.id)
      expect(response).to redirect_to(my_tasks_volunteer_tasks_path)
      expect(task.reload.status).to eq("completed")
      expect(flash.to_h).to be_empty
    end

    it "completes it for a regular user who has nothing to do with the task" do
      vol_login!(create(:user, :regular_user))
      get complete_task_volunteer_tasks_path(id: task.id)
      expect(task.reload.status).to eq("completed")
    end

    it "404s for a missing task" do
      get complete_task_volunteer_tasks_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "does not touch joins, requests, hours or CC money" do
      create(:volunteer_task_join, :active, volunteer_task: task)
      expect { get complete_task_volunteer_tasks_path(id: task.id) }
        .not_to change { [VolunteerTaskJoin.active.count, VolunteerHour.count, CcMoney.count] }
    end
  end

  describe "GET /volunteer_tasks/my_tasks" do
    %i[guest regular volunteer staff].each do |role|
      it "#{role}: renders (no gate)" do
        vol_sign_in_as(role)
        get my_tasks_volunteer_tasks_path
        expect(response).to have_http_status(:ok)
      end
    end

    it "lists the user's active joined tasks and approved requests" do
      create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
      other = create(:volunteer_task)
      create(:volunteer_task_join, :not_active, volunteer_task: other, user: volunteer)
      done = create(:volunteer_task_request, :approved, user: volunteer)
      create(:volunteer_task_request, :not_processed, user: volunteer)
      vol_login!(volunteer)
      get my_tasks_volunteer_tasks_path
      expect(ivar(:@your_volunteer_tasks)).to eq([task])
      expect(ivar(:@completed_task_requests)).to contain_exactly(done)
    end
  end
end
