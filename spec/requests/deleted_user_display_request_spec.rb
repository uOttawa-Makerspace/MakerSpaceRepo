# frozen_string_literal: true

require "rails_helper"

# A deleted account is hidden from public pages only: staff and admin pages keep showing the person,
# marked "(deleted account)", and pages that non-staff users open show a neutral label or nothing.
RSpec.describe "Pages that show a deleted user", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:gone) { create(:user, name: "Gone Person", username: "goneperson", email: "gone.person@uottawa.ca") }
  let(:gone_supervisor) { create(:user, :admin, name: "Gone Supervisor", username: "gonesupervisor") }
  let(:space) { create(:space) }

  def delete_account!(*users)
    users.each { |user| user.update_columns(deleted: true) }
  end

  def page_text
    Nokogiri::HTML(response.body).text.squish
  end

  def sign_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  describe "job order timeline (staff and admin)" do
    before { seed_job_statuses! }

    let(:order) do
      make_job_order!(owner: create(:user)).tap do |o|
        o.job_order_statuses.create!(job_status: JobStatus.being_processed, user: gone)
      end
    end

    it "names a deleted actor with the deleted-account mark and no profile link" do
      delete_account!(gone)
      sign_in!(staff)
      get job_order_timeline_modal_path(order)

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("(By: Gone Person (deleted account))")
      expect(page_text).not_to include("Unknown")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "still links a live actor to the profile" do
      sign_in!(staff)
      get job_order_timeline_modal_path(order)

      expect(response.body).to include(user_path(username: "goneperson"))
    end

    it "is closed to the customer" do
      delete_account!(gone)
      sign_in!(order.user)
      get job_order_timeline_modal_path(order)

      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include("Gone Person")
    end
  end

  describe "volunteer shadowing shifts" do
    before do
      ShadowingHour.create!(user: gone, space: space, event_id: "evt-1", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
      delete_account!(gone)
    end

    it "names the deleted volunteer and shows the email to staff" do
      sign_in!(staff)
      get shadowing_shifts_volunteers_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "gone.person@uottawa.ca")
      expect(response.body).to include("cancel Gone Person (deleted account)&#39;s shadowing shift")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "does not show a volunteer the list of other volunteers' shifts" do
      sign_in!(create(:user, :volunteer_with_volunteer_program))
      get shadowing_shifts_volunteers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Gone Person", "gone.person@uottawa.ca", "goneperson")
    end
  end

  describe "tap box console (staff)" do
    it "names the user of a log row and keeps the name in the search string" do
      TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "Door opened", user: gone)
      delete_account!(gone)
      sign_in!(staff)
      get staff_tap_box_console_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)")
      expect(response.body).to include("gone person")
    end
  end

  describe "admin keys" do
    let!(:key) do
      create(:key, :regular_key_type, :held_status, space: space, user: gone, supervisor: gone_supervisor)
    end
    let!(:key_request) do
      create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: gone, supervisor: gone_supervisor, space: space)
    end

    before do
      create(:key_certification, user: gone)
      delete_account!(gone, gone_supervisor)
      sign_in!(admin)
    end

    it "lists the holder, supervisor and email of a deleted holder" do
      get admin_keys_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "Gone Supervisor (deleted account)", "gone.person@uottawa.ca")
    end

    it "shows the holder, supervisor, email and request on the key page" do
      get admin_key_path(key)

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "Gone Supervisor (deleted account)", "gone.person@uottawa.ca")
      expect(page_text).to include("View Certifications")
    end

    it "lists the requester, supervisor and email on the requests page" do
      get requests_admin_keys_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "Gone Supervisor (deleted account)", "gone.person@uottawa.ca")
    end

    it "shows the requester, supervisor and email on the key request page" do
      get key_request_path(key_request)

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Gone Person (deleted account)", "Gone Supervisor (deleted account)", "gone.person@uottawa.ca")
    end
  end

  describe "key request page for a non-admin" do
    it "does not show another user's request to staff" do
      key_request = create(:key_request, :status_waiting_for_approval, :all_questions_answered, user: gone, supervisor: admin, space: space)
      delete_account!(gone)
      sign_in!(staff)
      get key_request_path(key_request)

      expect(response).to redirect_to(staff_dashboard_index_path)
      expect(response.body).not_to include("Gone Person")
    end
  end

  describe "orders (admin)" do
    it "names a deleted customer on the all-orders list and does not link the profile" do
      create(:order, :completed, user: gone)
      delete_account!(gone)
      sign_in!(admin)
      get orders_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("goneperson (deleted account)")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "does not list other customers' orders to a regular user" do
      create(:order, :completed, user: gone)
      delete_account!(gone)
      sign_in!(create(:user))
      get orders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("goneperson")
    end
  end

  describe "project proposal listings" do
    let!(:proposal) { create(:project_proposal, :joined, :approved, user: gone, admin: gone_supervisor) }

    before { delete_account!(gone, gone_supervisor) }

    it "names the proposer and reviewer to an admin" do
      sign_in!(admin)
      get projects_assigned_project_proposals_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("goneperson (deleted account)", "gonesupervisor (deleted account)")
      expect(response.body).not_to include(user_path(username: "goneperson"))
    end

    it "shows no proposer or reviewer to a regular user" do
      sign_in!(create(:user))
      get projects_assigned_project_proposals_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("goneperson", "gonesupervisor", "Gone Person")
    end
  end

  describe "certification counts in the key list" do
    let(:staff_files) { KeyCertification::NUMBER_OF_STAFF_FILES }

    before do
      allow_any_instance_of(KeyCertification).to receive(:get_key_certs_attached).and_return(7)
      sign_in!(admin)
    end

    it "shows no counts for a holder with a certification but no key request" do
      create(:key, :regular_key_type, :held_status, space: space, user: gone, supervisor: admin)
      create(:key_certification, user: gone)
      get admin_keys_path

      expect(response).to have_http_status(:ok)
      expect(page_text).to include("0/#{staff_files} (staff)")
      expect(page_text).not_to include("7/#{staff_files} (staff)")
    end

    it "shows the counts of a deleted holder who has a key request" do
      create(:key, :regular_key_type, :held_status, space: space, user: gone, supervisor: admin)
      create(:key_request, :status_approved, :all_questions_answered, user: gone, supervisor: admin, space: space)
      create(:key_certification, user: gone)
      delete_account!(gone)
      get admin_keys_path

      expect(page_text).to include("7/#{staff_files} (staff)")
    end
  end

  describe "the real associations" do
    before { delete_account!(gone, gone_supervisor) }

    it "hide a deleted account while the display associations return it" do
      key = create(:key, :regular_key_type, space: space, user: gone, supervisor: gone_supervisor)
      key_request = create(:key_request, :all_questions_answered, user: gone, supervisor: gone_supervisor, space: space)

      [key, key_request].each do |record|
        reloaded = record.class.find(record.id)
        expect(reloaded.user).to be_nil
        expect(reloaded.supervisor).to be_nil
        expect(reloaded.display_user).to eq(gone)
        expect(reloaded.display_supervisor).to eq(gone_supervisor)
      end
    end

    it "hide a deleted account on the other records too" do
      status = JobOrderStatus.new(user_id: gone.id)
      order = create(:order, user: create(:user)).tap { |o| o.update_columns(user_id: gone.id) }
      log = TapBoxLog.log!(event_type: TapBoxLog::INFO, message: "x", user: gone)
      shift = ShadowingHour.create!(user: gone, space: space)
      proposal = create(:project_proposal, user: gone, admin: gone_supervisor)

      expect([status, Order.find(order.id), log.reload, shift.reload, proposal.reload].map(&:user)).to all(be_nil)
      expect([status, Order.find(order.id), log.reload, shift.reload, proposal.reload].map(&:display_user)).to all(eq(gone))
      expect(proposal.admin).to be_nil
      expect(proposal.display_admin).to eq(gone_supervisor)
    end
  end
end
