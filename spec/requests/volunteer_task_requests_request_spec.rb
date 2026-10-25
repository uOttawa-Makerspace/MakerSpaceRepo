# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteerTaskRequestsController. No role gate on any action; only
# the listing scope differs for staff. Approval creates CC money and an approved
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

  describe "GET /volunteer_task_requests/create_request" do
    def request!(id = task.id, headers: {})
      perform_enqueued_jobs { get create_request_volunteer_task_requests_path(id: id), headers: headers }
    end

    it "creates a pending request, redirects back with a notice, emails the requester with staff bcc'd" do
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

    # WART(D-V16): no uniqueness / status check: duplicate requests, and requests on completed tasks, are accepted
    it "accepts duplicate requests and requests for a completed task" do
      task.update!(status: "completed")
      vol_login!(volunteer)
      expect { 2.times { request! } }.to change(VolunteerTaskRequest, :count).by(2)
      expect(vol_deliveries.size).to eq(2)
    end

    it "lets a regular user (no program) request a task" do
      user = create(:user, :regular_user)
      vol_login!(user)
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
    end

    # WART(D-V17): a guest persists an orphan request (user_id NULL); the mailer then raises RecordNotFound (404)
    it "stores an orphan request for a guest and then 404s on the mail" do
      expect { request! }.to change(VolunteerTaskRequest, :count).by(1)
      expect(VolunteerTaskRequest.last.user_id).to be_nil
      expect(response).to have_http_status(:not_found)
      expect(vol_deliveries).to be_empty
    end

    it "404s for a nonexistent task and creates nothing" do
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

      it "rejects: marks approval false, deactivates the join, awards nothing, still emails" do
        join = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
        expect { approve!("false") }.not_to change { [CcMoney.count, VolunteerHour.count] }
        expect(req.reload.approval).to be(false)
        expect(join.reload.active).to be(false)
        expect(vol_deliveries.map(&:subject)).to eq(["Your request was updated: Tour guide"])
      end

      # WART(D-V18): approving again re-awards CC and hours and re-emails (no processed-state check)
      it "double-awards CC money and hours when approved twice" do
        approve!("true")
        expect { approve!("true") }.to change(CcMoney, :count).by(1).and change(VolunteerHour, :count).by(1)
        expect(volunteer.reload.wallet).to eq(24)
        expect(vol_deliveries.size).to eq(2)
      end

      it "treats a missing approval param as 'unprocessed': deactivates the join and still emails" do
        join = create(:volunteer_task_join, :active, volunteer_task: task, user: volunteer)
        put update_approval_volunteer_task_requests_path, params: { id: req.id }
        expect(req.reload.approval).to be_nil
        expect(join.reload.active).to be(false)
        expect(response).to redirect_to(volunteer_task_requests_path)
      end

      it "404s for a missing request" do
        approve!("true", id: 999_999)
        expect(response).to have_http_status(:not_found)
      end
    end

    # WART(D-V19): update_approval has no sign-in/role gate: the requester (and a guest) approves the request, minting CC money and hours
    it "lets the requesting volunteer approve their own request" do
      vol_login!(volunteer)
      expect { approve!("true") }.to change(CcMoney, :count).by(1).and change(VolunteerHour, :count).by(1)
      expect(req.reload.approval).to be(true)
      expect(volunteer.reload.get_total_hours).to eq(3.5)
    end

    it "lets a GUEST approve a request" do
      expect { approve!("true") }.to change(CcMoney, :count).by(1)
      expect(req.reload.approval).to be(true)
      expect(response).to redirect_to(volunteer_task_requests_path)
    end

    it "500s for an orphan request (no user)" do
      orphan = VolunteerTaskRequest.create!(volunteer_task: task)
      approve!("true", id: orphan.id)
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
