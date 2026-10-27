# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerTaskRequestsController. No role gate except update_approval
# (sign-in + staff, D-V19); the listing scope differs for staff. Approval creates CC money and an approved
# VolunteerHour and emails the requester.
RSpec.describe "Volunteer task requests (HTTP contract)", type: :request do
  let(:task) { create(:volunteer_task, title: "tour guide", cc: 12, hours: 3.5) }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let(:other_volunteer) { create(:user, :volunteer_with_volunteer_program) }

  before { ActionMailer::Base.deliveries.clear }

  def ivar(name)
    controller.instance_variable_get(name)
  end

  describe "GET /volunteer_task_requests (index)" do
    %i[guest regular volunteer staff admin].each do |role|
      it "#{role}: renders (no role gate)" do
        vol_sign_in_as(role)
        get volunteer_task_requests_path
        expect(response).to have_http_status(:ok)
      end
    end

    it "shows a volunteer only their own requests, with counts" do
      mine = create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task)
      create(:volunteer_task_request, :approved, user: volunteer, volunteer_task: task)
      theirs = create(:volunteer_task_request, :not_processed, user: other_volunteer, volunteer_task: task)
      vol_login!(volunteer)
      get volunteer_task_requests_path
      expect(ivar(:@pending_volunteer_task_requests)).to contain_exactly(mine)
      expect(ivar(:@pending_volunteer_task_requests)).not_to include(theirs)
      expect([ivar(:@total_count), ivar(:@pending_count), ivar(:@processed_count)]).to eq([2, 1, 1])
    end

    it "shows staff every request" do
      create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task)
      create(:volunteer_task_request, :rejected, user: other_volunteer, volunteer_task: task)
      vol_login!(create(:user, :staff))
      get volunteer_task_requests_path
      expect([ivar(:@total_count), ivar(:@pending_count), ivar(:@processed_count)]).to eq([2, 1, 1])
    end

    it "picks the active tab from params (default pending; processed when page_processed is given)" do
      vol_login!(volunteer)
      get volunteer_task_requests_path
      expect(ivar(:@active_tab)).to eq("pending")
      get volunteer_task_requests_path(page_processed: 1)
      expect(ivar(:@active_tab)).to eq("processed")
      get volunteer_task_requests_path(tab: "anything")
      expect(ivar(:@active_tab)).to eq("anything")
    end

    it "filters the pending list by search term (volunteer name, task title or space)" do
      match = create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task)
      other_task = create(:volunteer_task, title: "zzz")
      create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: other_task)
      vol_login!(volunteer)
      get volunteer_task_requests_path(search_pending: "TOUR")
      expect(ivar(:@pending_volunteer_task_requests)).to contain_exactly(match)
    end
  end

  describe "GET search_pending / search_processed (partials)" do
    it "renders the pending partial scoped to the user and the processed partial likewise" do
      create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task)
      create(:volunteer_task_request, :approved, user: volunteer, volunteer_task: task)
      vol_login!(volunteer)
      get search_pending_volunteer_task_requests_path(search_pending: "tour")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<html")
      expect(ivar(:@pending_volunteer_task_requests).size).to eq(1)
      get search_processed_volunteer_task_requests_path(search_processed: "nomatch")
      expect(response).to have_http_status(:ok)
      expect(ivar(:@processed_volunteer_task_requests)).to be_empty
    end

    it "renders for a guest with empty results (no gate)" do
      get search_pending_volunteer_task_requests_path
      expect(response).to have_http_status(:ok)
      get search_processed_volunteer_task_requests_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /volunteer_task_requests/create_request" do
    def assign!(user, to: task)
      create(:volunteer_task_join, :active, volunteer_task: to, user: user)
    end

    def request!(id = task.id, headers: {})
      perform_enqueued_jobs { post create_request_volunteer_task_requests_path(id: id), headers: headers }
    end

    it "creates nothing on a plain GET" do
      assign!(volunteer)
      vol_login!(volunteer)
      expect { get "/volunteer_task_requests/create_request", params: { id: task.id } }.not_to change(VolunteerTaskRequest, :count)
    end

    it "creates a pending request, redirects back with a notice, emails the requester with staff bcc'd" do
      assign!(volunteer)
      vol_login!(volunteer)
      expect { request!(headers: { "HTTP_REFERER" => volunteer_task_url(task) }) }
        .to change(VolunteerTaskRequest, :count).by(1)
      expect(response).to redirect_to(volunteer_task_url(task))
      expect(flash[:notice]).to eq("You've sent a request. No further action is needed.")
      req = VolunteerTaskRequest.last
      expect([req.user_id, req.volunteer_task_id, req.approval]).to eq([volunteer.id, task.id, nil])
      expect(vol_deliveries.size).to eq(1)
      mail = vol_deliveries.first
      expect(mail.to).to eq([volunteer.email])
      expect(mail.bcc).to eq(["volunteer@makerepo.com"])
      expect(mail.subject).to eq("New Request for task: Tour guide")
    end

    # FIXED(D-V16, uniqueness part): no second open/approved request per user and task. The status part was dropped: assigned volunteers may still submit after staff mark the task completed
    it "refuses a duplicate pending request and sends no second email" do
      assign!(volunteer)
      vol_login!(volunteer)
      request!
      expect { request! }.not_to change { [VolunteerTaskRequest.count, vol_deliveries.size] }
      expect(flash[:alert]).to eq("You have already sent a request for this task.")
    end

    it "refuses a new request after an approved one" do
      create(:volunteer_task_request, :approved, user: volunteer, volunteer_task: task)
      assign!(volunteer)
      vol_login!(volunteer)
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
    end

    # FIXED(rejection keeps the join): the real flow, using the original join after a staff rejection
    it "accepts a new request after a staff rejection, on the original join" do
      join = assign!(volunteer)
      vol_login!(volunteer)
      request!
      vol_login!(create(:user, :staff))
      put update_approval_volunteer_task_requests_path, params: { id: VolunteerTaskRequest.last.id, approval: "false" }
      expect(join.reload.active).to be(true)
      vol_login!(volunteer)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    it "lets an assigned volunteer submit after staff marked the task completed" do
      task.update!(status: "completed")
      assign!(volunteer)
      vol_login!(volunteer)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    it "refuses an unassigned user on a completed task" do
      task.update!(status: "completed")
      vol_login!(volunteer)
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
    end

    it "lets two different users each request the same task" do
      assign!(volunteer)
      vol_login!(volunteer)
      request!
      assign!(other_volunteer)
      vol_login!(other_volunteer)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    # INTENDED(D-V14, role part of D-V16): requests stay open to any signed-in user (enrolment is open by design)
    it "lets a regular user (no program) request a task" do
      user = create(:user, :regular_user)
      assign!(user)
      vol_login!(user)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    # FIXED(create_request assignment): only a user with an active join on the task may file the request
    it "refuses a user who never joined the task and creates nothing" do
      vol_login!(volunteer)
      expect { request! }.not_to change { [VolunteerTaskRequest.count, vol_deliveries.size] }
      expect(flash[:alert]).to eq("You must be assigned to this task to submit it.")
    end

    it "refuses a user whose join is no longer active" do
      create(:volunteer_task_join, :not_active, volunteer_task: task, user: volunteer)
      vol_login!(volunteer)
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
    end

    it "refuses a user who is joined to a different task only" do
      assign!(volunteer, to: create(:volunteer_task))
      vol_login!(volunteer)
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
    end

    it "refuses unassigned staff" do
      vol_login!(create(:user, :staff))
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
    end

    it "lets assigned staff file the request" do
      staff = create(:user, :staff)
      create(:volunteer_task_join, :active_not_volunteer, volunteer_task: task, user: staff)
      vol_login!(staff)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    # FIXED(D-V17): a guest is sent to login and nothing is persisted
    it "redirects a guest to login without storing an orphan request" do
      expect { request! }.not_to change(VolunteerTaskRequest, :count)
      expect(response).to redirect_to(login_path(back_to: create_request_volunteer_task_requests_path(id: task.id)))
      expect(vol_deliveries).to be_empty
    end

    it "404s for a nonexistent task and creates nothing" do
      assign!(volunteer)
      vol_login!(volunteer)
      expect { request!(999_999) }.not_to change(VolunteerTaskRequest, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /volunteer_task_requests/update_approval" do
    let!(:req) { create(:volunteer_task_request, :not_processed, user: volunteer, volunteer_task: task) }

    def approve!(approval, id: req.id)
      perform_enqueued_jobs { put update_approval_volunteer_task_requests_path, params: { id: id, approval: approval } }
    end

    context "approving as staff" do
      before { vol_login!(create(:user, :staff)) }

      it "approves, deactivates the join, creates CC money + approved hours, updates the wallet and emails the requester" do
        join = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
        approve!("true")
        expect(response).to redirect_to(volunteer_task_requests_path)
        expect(flash[:notice]).to eq("Task request updated")
        expect(req.reload.approval).to be(true)
        expect(join.reload.active).to be(false)

        money = CcMoney.last
        expect([money.user_id, money.volunteer_task_id, money.cc]).to eq([volunteer.id, task.id, 12])
        expect(volunteer.reload.wallet).to eq(12)
        hour = VolunteerHour.last
        expect([hour.user_id, hour.volunteer_task_id, hour.total_time, hour.approval]).to eq([volunteer.id, task.id, 3.5, true])

        expect(vol_deliveries.map { |m| [m.to, m.subject] }).to eq(
          [[[volunteer.email], "Your request was updated: Tour guide"]]
        )
      end

      it "rejects: marks approval false, keeps the join active so the volunteer can resubmit, awards nothing, still emails" do
        join = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
        expect { approve!("false") }.not_to change { [CcMoney.count, VolunteerHour.count] }
        expect(req.reload.approval).to be(false)
        expect(join.reload.active).to be(true)
        expect(vol_deliveries.map(&:subject)).to eq(["Your request was updated: Tour guide"])
      end

      # FIXED(D-V18): approving an already-approved request is a no-op (no second award, no second email)
      it "awards CC money and hours only once when approved twice" do
        approve!("true")
        expect { approve!("true") }.not_to change { [CcMoney.count, VolunteerHour.count, vol_deliveries.size] }
        expect(volunteer.reload.wallet).to eq(12)
        expect(flash[:notice]).to eq("Task request was already approved")
        expect(response).to redirect_to(volunteer_task_requests_path)
        expect(vol_deliveries.size).to eq(1)
      end

      # FIXED(D-V29): the award is paid at most once per user and task, whatever the approval history
      it "pays only once for approve -> reject -> approve" do
        approve!("true")
        approve!("false")
        expect { approve!("true") }.not_to change { [CcMoney.count, VolunteerHour.count] }
        expect(req.reload.approval).to be(true)
        expect(volunteer.reload.wallet).to eq(12)
        expect(volunteer.get_total_hours).to eq(3.5)
      end

      it "pays only once for approve -> unprocessed -> approve" do
        approve!("true")
        put update_approval_volunteer_task_requests_path, params: { id: req.id }
        expect(req.reload.approval).to be_nil
        expect { approve!("true") }.not_to change { [CcMoney.count, VolunteerHour.count] }
      end

      it "takes the row lock while approving" do
        expect_any_instance_of(VolunteerTaskRequest).to receive(:with_lock).and_call_original
        approve!("true")
        expect(CcMoney.count).to eq(1)
      end

      it "treats a missing approval param as 'unprocessed': keeps the join and still emails" do
        join = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
        put update_approval_volunteer_task_requests_path, params: { id: req.id }
        expect(req.reload.approval).to be_nil
        expect(join.reload.active).to be(true)
        expect(response).to redirect_to(volunteer_task_requests_path)
      end

      it "404s for a missing request" do
        approve!("true", id: 999_999)
        expect(response).to have_http_status(:not_found)
      end
    end

    # FIXED(D-V19): update_approval requires sign-in and staff/admin
    {
      "the requesting volunteer" => ->(ex) { ex.volunteer },
      "another volunteer" => ->(ex) { ex.other_volunteer },
      "a regular user" => ->(_ex) { FactoryBot.create(:user, :regular_user) }
    }.each do |who, user|
      it "refuses #{who} and awards nothing" do
        vol_login!(user.call(self))
        expect { approve!("true") }.not_to change { [CcMoney.count, VolunteerHour.count] }
        expect(req.reload.approval).to be_nil
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
        expect(vol_deliveries).to be_empty
      end
    end

    it "redirects a GUEST to login and awards nothing" do
      expect { approve!("true") }.not_to change { [CcMoney.count, VolunteerHour.count] }
      expect(req.reload.approval).to be_nil
      expect(response).to redirect_to(login_path(back_to: update_approval_volunteer_task_requests_path))
    end

    it "lets an admin approve" do
      vol_login!(create(:user, :admin))
      expect { approve!("true") }.to change(CcMoney, :count).by(1).and change(VolunteerHour, :count).by(1)
      expect(req.reload.approval).to be(true)
    end

    it "500s for an orphan request (no user)" do
      vol_login!(create(:user, :staff))
      orphan = VolunteerTaskRequest.create!(volunteer_task: task)
      approve!("true", id: orphan.id)
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
