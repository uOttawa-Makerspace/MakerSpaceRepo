# frozen_string_literal: true

require "rails_helper"

# Chunk 13: VolunteersController (+ shadowing shifts).
#   index                       open to everyone (guests too)
#   join_volunteer_program      signed in
#   transcript                  inline sign-in check; own transcript, or any user for staff
#   emails, my_stats, calendar, populate_users, shadowing_shifts
#                               volunteer-program member, staff or admin (`grant_access`)
#   volunteer_list, new_event, create_event, delete_event
#                               staff/admin only (`grant_access_list`)
# Google Calendar is never reached: ShadowingHour.create_event/delete_event are stubbed.
RSpec.describe "Volunteers (HTTP contract)", type: :request do
  HUBSPOT_URL = "https://5oe8xl.share-na3.hsforms.com/20slW0brbQJCsdeEck-8vuQ"

  def ivar(name)
    controller.instance_variable_get(name)
  end

  describe "GET /volunteers (index)" do
    %i[guest regular role_only volunteer staff admin].each do |role|
      it "#{role}: renders" do
        vol_sign_in_as(role)
        get volunteers_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "volunteer-area gate (grant_access)" do
    { emails: :emails_volunteers_path, my_stats: :my_stats_volunteers_path, calendar: :calendar_volunteers_path,
      populate_users: :populate_users_volunteers_path, shadowing_shifts: :shadowing_shifts_volunteers_path }.each do |action, helper|
      %i[guest regular role_only].each do |role|
        it "#{role}: #{action} redirects to root with an alert" do
          vol_sign_in_as(role)
          get send(helper)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("You cannot access this area.")
        end
      end

      %i[volunteer inactive staff admin].each do |role|
        it "#{role}: #{action} renders" do
          vol_sign_in_as(role)
          get send(helper)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe "staff-only gate (grant_access_list)" do
    { volunteer_list: :volunteer_list_volunteers_path, new_event: :new_event_volunteers_path,
      create_event: :create_event_volunteers_path, delete_event: :delete_event_volunteers_path }.each do |action, helper|
      %i[guest regular role_only volunteer inactive].each do |role|
        it "#{role}: #{action} redirects to root with an alert" do
          vol_sign_in_as(role)
          get send(helper)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("You cannot access this area.")
        end
      end
    end

    %i[staff admin].each do |role|
      it "#{role}: volunteer_list and new_event render" do
        vol_sign_in_as(role)
        get volunteer_list_volunteers_path
        expect(response).to have_http_status(:ok)
        get new_event_volunteers_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /volunteers/volunteer_list" do
    it "splits volunteers by the program's active flag, ordered by name" do
      active_b = create(:user, :volunteer_with_volunteer_program, name: "Bea")
      active_a = create(:user, :volunteer_with_volunteer_program, name: "Abe")
      inactive = create(:user, :unactive_volunteer_with_volunteer_program, name: "Zed")
      create(:user, :regular_user)
      vol_login!(create(:user, :staff))
      get volunteer_list_volunteers_path
      expect(ivar(:@active_volunteers)).to eq([active_a, active_b])
      expect(ivar(:@unactive_volunteers)).to eq([inactive])
    end
  end

  describe "GET /volunteers/emails" do
    it "lists volunteer emails: all, active and inactive" do
      a = create(:user, :volunteer_with_volunteer_program)
      i = create(:user, :unactive_volunteer_with_volunteer_program)
      r = create(:user, :regular_user)
      vol_login!(a)
      get emails_volunteers_path
      expect(ivar(:@all_emails)).to contain_exactly(a.email, i.email)
      expect(ivar(:@active_emails)).to eq([a.email])
      expect(ivar(:@unactive_emails)).to eq([i.email])
      expect(response.body).to include(i.email)
      expect(response.body).not_to include(r.email)
    end

    # WART(D-V24): any volunteer (not just staff) reads every volunteer's email, and the program is self-service (join_volunteer_program), so any signed-in user can reach this
    it "is reachable by a regular user after self-enrolling through join_volunteer_program" do
      victim = create(:user, :volunteer_with_volunteer_program)
      user = create(:user, :regular_user)
      vol_login!(user)
      get emails_volunteers_path
      expect(response).to redirect_to(root_path)
      get join_volunteer_program_volunteers_path
      get emails_volunteers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(victim.email)
    end
  end

  describe "GET /volunteers/populate_users" do
    it "returns volunteers as JSON, filtered case-insensitively by name" do
      match = create(:user, :volunteer_with_volunteer_program, name: "Marta Query")
      create(:user, :volunteer_with_volunteer_program, name: "Someone Else")
      create(:user, :regular_user, name: "Marta Regular")
      vol_login!(create(:user, :volunteer_with_volunteer_program))
      get populate_users_volunteers_path(search: "mARTA")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      body = JSON.parse(response.body)
      expect(body.keys).to eq(["users"])
      expect(body["users"].map { |u| u["id"] }).to eq([match.id])
    end

    # WART(D-V25): the JSON is the raw User#as_json (email, student_id, flags, and the password column) for any volunteer
    it "exposes the full user record, including the password hash, to a plain volunteer" do
      target = create(:user, :volunteer_with_volunteer_program, name: "Target Person")
      vol_login!(create(:user, :volunteer_with_volunteer_program))
      get populate_users_volunteers_path(search: "target")
      row = JSON.parse(response.body)["users"].first
      expect(row).to include("email" => target.email, "username" => target.username, "role" => "volunteer")
      expect(row).to have_key("student_id")
      expect(row["password"]).to start_with("$2")
    end

    it "returns every volunteer when search is blank" do
      create_list(:user, 2, :volunteer_with_volunteer_program)
      vol_login!(create(:user, :staff))
      get populate_users_volunteers_path
      expect(JSON.parse(response.body)["users"].size).to eq(2)
    end
  end

  describe "join_volunteer_program (GET and POST)" do
    %i[get post].each do |verb|
      it "#{verb}: guest is sent to login with back_to" do
        send(verb, join_volunteer_program_volunteers_path)
        expect(response).to redirect_to(login_path(back_to: join_volunteer_program_volunteers_path))
        expect(Program.count).to eq(0)
      end

      it "#{verb}: a regular user is enrolled (active) and sent to the external HubSpot form" do
        user = create(:user, :regular_user)
        vol_login!(user)
        expect { send(verb, join_volunteer_program_volunteers_path) }.to change(Program, :count).by(1)
        expect(response).to redirect_to(HUBSPOT_URL)
        expect(flash[:notice]).to eq("You've joined the Volunteer Program")
        program = user.programs.last
        expect([program.program_type, program.active]).to eq([Program::VOLUNTEER, true])
        expect(user.reload.role).to eq("regular_user")
        expect(user.volunteer?).to be(true)
      end

      it "#{verb}: staff are not enrolled; notice says they already have access" do
        staff = create(:user, :staff)
        vol_login!(staff)
        expect { send(verb, join_volunteer_program_volunteers_path) }.not_to change(Program, :count)
        expect(response).to redirect_to(HUBSPOT_URL)
        expect(flash[:notice]).to eq("You already have access to the Volunteer Program.")
      end
    end

    # WART(D-V26): enrolment is a one-request, unapproved GET that grants volunteer access (emails, volunteer list JSON, tasks); GET mutates state
    it "gives instant access to the volunteer area" do
      vol_login!(create(:user, :regular_user))
      get join_volunteer_program_volunteers_path
      get volunteer_tasks_path
      expect(response).to have_http_status(:ok)
    end

    it "does not duplicate the enrolment and still flashes success" do
      user = create(:user, :volunteer_with_volunteer_program)
      vol_login!(user)
      expect { get join_volunteer_program_volunteers_path }.not_to change(Program, :count)
      expect(flash[:notice]).to eq("You've joined the Volunteer Program")
    end

    it "does not reactivate an inactive membership" do
      user = create(:user, :unactive_volunteer_with_volunteer_program)
      vol_login!(user)
      get join_volunteer_program_volunteers_path
      expect(user.programs.sole.active).to be(false)
    end
  end

  describe "GET /volunteers/transcript" do
    it "sends a guest to login with an alert" do
      get transcript_volunteers_path
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq("Please sign in to view your volunteer transcript.")
    end

    it "renders a regular user's own transcript without the layout (no volunteer gate)" do
      user = create(:user, :regular_user)
      vol_login!(user)
      get transcript_volunteers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<nav")
      expect(ivar(:@volunteer)).to eq(user)
    end

    it "computes totals from approved requests, approved hours and CC money" do
      user = create(:user, :volunteer_with_volunteer_program)
      create(:volunteer_hour, :approved1, user: user)
      create(:volunteer_hour, :not_processed, user: user)
      create(:cc_money, user: user, cc: 30)
      approved = create(:volunteer_task_request, :approved, user: user)
      create(:volunteer_task_request, :not_processed, user: user)
      vol_login!(user)
      get transcript_volunteers_path
      expect(ivar(:@total_hours)).to eq(10)
      expect(ivar(:@total_cc)).to eq(30)
      expect(ivar(:@approved_task_requests)).to eq([approved])
    end

    it "lets staff view another user's transcript via user_id" do
      target = create(:user, :volunteer_with_volunteer_program)
      vol_login!(create(:user, :staff))
      get transcript_volunteers_path(user_id: target.id)
      expect(ivar(:@volunteer)).to eq(target)
    end

    it "falls back to the staff user's own transcript for an unknown user_id" do
      staff = create(:user, :admin)
      vol_login!(staff)
      get transcript_volunteers_path(user_id: 999_999)
      expect(ivar(:@volunteer)).to eq(staff)
    end

    it "ignores user_id for non-staff" do
      target = create(:user, :volunteer_with_volunteer_program)
      me = create(:user, :volunteer_with_volunteer_program)
      vol_login!(me)
      get transcript_volunteers_path(user_id: target.id)
      expect(ivar(:@volunteer)).to eq(me)
    end
  end

  describe "GET /volunteers/my_stats" do
    it "paginates the user's approved processed requests" do
      user = create(:user, :volunteer_with_volunteer_program)
      create_list(:volunteer_task_request, 2, :approved, user: user)
      create(:volunteer_task_request, :rejected, user: user)
      create(:volunteer_task_request, :approved)
      vol_login!(user)
      get my_stats_volunteers_path
      expect(response).to have_http_status(:ok)
      expect(ivar(:@processed_volunteer_task_requests).size).to eq(2)
    end
  end

  describe "shadowing" do
    let!(:makerspace) { Space.find_by("LOWER(name) = ?", "makerspace") || create(:space, name: "Makerspace") }
    let(:staff) { create(:user, :staff) }
    let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
    let(:event) { double("event", id: "evt-123", status: "confirmed") }

    describe "GET shadowing_shifts" do
      it "shows the user's own future shifts and every future shift" do
        mine = ShadowingHour.create!(user: volunteer, space: makerspace, start_time: 1.day.from_now, end_time: 2.days.from_now, event_id: "a")
        theirs = ShadowingHour.create!(user: staff, space: makerspace, start_time: 1.day.from_now, end_time: 2.days.from_now, event_id: "b")
        ShadowingHour.create!(user: volunteer, space: makerspace, start_time: 3.days.ago, end_time: 2.days.ago, event_id: "c")
        vol_login!(volunteer)
        get shadowing_shifts_volunteers_path
        expect(ivar(:@shifts)).to eq([mine])
        expect(ivar(:@all_shifts)).to contain_exactly(mine, theirs)
      end
    end

    describe "GET create_event" do
      let(:params) do
        { space: "makerspace", datepicker_start: "2030-05-06 09:00", datepicker_end: "2030-05-06 11:30", user_id: volunteer.id }
      end

      before { vol_login!(staff) }

      it "creates the calendar event and a ShadowingHour, redirecting to the calendar" do
        expect(ShadowingHour).to receive(:create_event)
          .with("2030-05-06T 9:00:00", "2030-05-06T11:30:00", volunteer, "makerspace").and_return(event)
        expect { get create_event_volunteers_path, params: params }.to change(ShadowingHour, :count).by(1)
        expect(response).to redirect_to(calendar_volunteers_path)
        expect(flash[:notice]).to eq("The shadowing shift has been added")
        shift = ShadowingHour.last
        expect([shift.user_id, shift.event_id, shift.space_id]).to eq([volunteer.id, "evt-123", makerspace.id])
        expect(shift.start_time.strftime("%H:%M")).to eq("09:00")
        expect(shift.end_time.strftime("%H:%M")).to eq("11:30")
      end

      it "flashes an error and stores nothing when Google reports the event cancelled" do
        allow(ShadowingHour).to receive(:create_event).and_return(double(id: "x", status: "cancelled"))
        expect { get create_event_volunteers_path, params: params }.not_to change(ShadowingHour, :count)
        expect(response).to redirect_to(calendar_volunteers_path)
        expect(flash[:alert]).to eq("An Error occurred")
      end

      it "rejects an unknown space name without calling Google" do
        expect(ShadowingHour).not_to receive(:create_event)
        get create_event_volunteers_path, params: params.merge(space: "garage")
        expect(response).to redirect_to(calendar_volunteers_path)
        expect(flash[:alert]).to eq("An error occurred, please make sure you choose a space.")
      end

      it "rejects missing dates or user_id" do
        expect(ShadowingHour).not_to receive(:create_event)
        get create_event_volunteers_path, params: params.except(:datepicker_end)
        expect(flash[:alert]).to eq("An error occurred, please make sure you choose a space.")
        get create_event_volunteers_path, params: params.except(:user_id)
        expect(flash[:alert]).to eq("An error occurred, please make sure you choose a space.")
      end

      it "404s for a nonexistent user_id" do
        get create_event_volunteers_path, params: params.merge(user_id: 999_999)
        expect(response).to have_http_status(:not_found)
      end

      # WART(D-V27): any user id is accepted (not only volunteers); a state-changing GET
      it "books a shift for a non-volunteer user" do
        allow(ShadowingHour).to receive(:create_event).and_return(event)
        regular = create(:user, :regular_user)
        expect { get create_event_volunteers_path, params: params.merge(user_id: regular.id) }
          .to change(ShadowingHour, :count).by(1)
      end

      # WART(D-V28): the calendar event is created BEFORE the space row is looked up; a missing Space row 500s and leaves an orphan Google event
      it "500s after calling Google when no Space matches the name" do
        Space.where("LOWER(name) = 'makerspace'").destroy_all
        expect(ShadowingHour).to receive(:create_event).and_return(event)
        expect { get create_event_volunteers_path, params: params }.not_to change(ShadowingHour, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "accepts 'brunsfield centre' as a space" do
        brunsfield = create(:space, name: "Brunsfield Centre")
        expect(ShadowingHour).to receive(:create_event).with(anything, anything, volunteer, "brunsfield centre").and_return(event)
        get create_event_volunteers_path, params: params.merge(space: "brunsfield centre")
        expect(ShadowingHour.last.space_id).to eq(brunsfield.id)
      end
    end

    describe "GET delete_event" do
      let!(:shift) { ShadowingHour.create!(user: volunteer, space: makerspace, start_time: 1.day.from_now, end_time: 2.days.from_now, event_id: "evt-9") }

      before { vol_login!(staff) }

      it "deletes the calendar event (by the space's name) and the row" do
        expect(ShadowingHour).to receive(:delete_event).with("evt-9", makerspace.name).and_return(double)
        expect { get delete_event_volunteers_path(event_id: "evt-9") }.to change(ShadowingHour, :count).by(-1)
        expect(response).to redirect_to(calendar_volunteers_path)
        expect(flash[:notice]).to eq("This shift has been cancelled.")
      end

      it "keeps the row and alerts when Google returns 'error'" do
        allow(ShadowingHour).to receive(:delete_event).and_return("error")
        expect { get delete_event_volunteers_path(event_id: "evt-9") }.not_to change(ShadowingHour, :count)
        expect(flash[:alert]).to eq("An error occured while deleting the shift.")
      end

      it "alerts for an unknown or missing event_id without calling Google" do
        expect(ShadowingHour).not_to receive(:delete_event)
        get delete_event_volunteers_path(event_id: "nope")
        expect(flash[:alert]).to eq("This shift has not been found.")
        get delete_event_volunteers_path
        expect(flash[:alert]).to eq("This shift has not been found.")
        expect(response).to redirect_to(calendar_volunteers_path)
      end
    end
  end
end
