require "rails_helper"

RSpec.describe Admin::EventsController, type: :controller do
  let(:admin_user) { create(:user, :admin) }
  let(:space) { create(:space) }
  let(:event) { create(:event, space: space, created_by: admin_user) }
  let(:staff_members) { create_list(:user, 2, :staff) }

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = admin_user.id
  end

  describe "POST #create" do
    it "creates an event with assignments" do
      post :create, params: {
        event: {
          title: "",
          description: "Planning",
          utc_start_time: 1.day.from_now.utc.iso8601,
          utc_end_time: (1.day.from_now + 2.hours).utc.iso8601,
          event_type: "meeting",
          recurrence_rule: "",
          space_id: space.id
        },
        staff_select: staff_members.map(&:id)
      }

      expect(Event.count).to eq(1)
      expect(EventAssignment.count).to eq(2)
      expect(flash[:notice]).to eq("Event created successfully.")
    end
  end

  describe "PATCH #update" do
    context "with non-recurring event" do
      it "updates the event and assignments" do
        event.event_assignments.create!(user: staff_members.first)

        patch :update, params: {
          id: event.id,
          event: {
            title: "Updated Event",
            description: "Updated",
            utc_start_time: event.start_time.iso8601,
            utc_end_time: event.end_time.iso8601,
            event_type: event.event_type,
            recurrence_rule: "",
            space_id: space.id
          },
          staff_select: [staff_members.last.id]
        }

        expect(event.reload.title).to eq("Updated Event")
        expect(event.event_assignments.map(&:user_id)).to eq([staff_members.last.id])
      end
    end

    context "with recurring event updating all" do
      let!(:recurring_event) { create(:event, :recurring, space: space, created_by: admin_user) }

      it "updates title" do
        patch :update, params: {
          id: recurring_event.id,
          update_scope: "all",
          event: {
            title: "Recurring Update",
            description: "desc",
            utc_start_time: recurring_event.start_time,
            utc_end_time: recurring_event.end_time,
            recurrence_rule: recurring_event.recurrence_rule,
            event_type: recurring_event.event_type, 
            space_id: space.id
          },
          staff_select: [staff_members.first.id]
        }

        expect(recurring_event.reload.title).to eq("Recurring Update")
        expect(recurring_event.event_assignments.map(&:user_id)).to eq([staff_members.first.id])
      end
    end

    context "with recurring event updating all from the night the clocks go back" do
      let(:first) { Time.zone.local(2027, 10, 31, 1, 30) }
      let!(:weekly) do
        create(:event, space: space, created_by: admin_user, event_type: "other", title: "Sunday lab",
                       start_time: first, end_time: first + 1.hour,
                       recurrence_rule: "DTSTART:20271031T053000Z\nRRULE:FREQ=WEEKLY;BYDAY=SU")
      end
      let(:posted) do
        { title: "Renamed", event_type: "other", space_id: space.id, utc_start_time: "2027-11-07T05:30:00Z",
          utc_end_time: "2027-11-07T07:30:00Z", recurrence_rule: "DTSTART;TZID=America/Toronto:20271107T013000\nRRULE:FREQ=WEEKLY;BYDAY=SU" }
      end

      # The dialog posts the form's wall times, 01:30 to 02:30, which are two real hours that night.
      it "keeps the series' start and length when the times are as the dialog filled them" do
        patch :update, params: { id: weekly.id, update_scope: "all", keep_series_times: "1", event: posted }

        expect(weekly.reload).to have_attributes(title: "Renamed", start_time: first, end_time: first + 1.hour)
      end

      it "takes the posted length when the times were changed" do
        patch :update, params: { id: weekly.id, update_scope: "all", event: posted }

        expect(weekly.reload).to have_attributes(start_time: first, end_time: first + 2.hours)
      end
    end

    context "with recurring event updating this occurrence only" do
      let!(:recurring_event) { create(:event, :recurring, space: space, created_by: admin_user) }

      it "adds EXDATE and creates a new event" do
        expect do
          patch :update, params: {
            id: recurring_event.id,
            update_scope: "this",
            event: {
              title: "One-time change",
              description: "Only one",
              utc_start_time: recurring_event.start_time.iso8601,
              utc_end_time: recurring_event.end_time.iso8601,
              recurrence_rule: recurring_event.recurrence_rule,
              event_type: recurring_event.event_type,
              space_id: space.id
            },
            staff_select: [staff_members.first.id]
          }
        end.to change(Event, :count).by(1)

        expect(Event.last.title).to eq("One-time change")
      end
    end
  end

  describe "DELETE #delete_with_scope" do
    let!(:recurring_event) { create(:event, :recurring, space: space, created_by: admin_user) }

    it "deletes single occurrence by adding EXDATE" do
      expect do
        delete :delete_with_scope, params: {
          id: recurring_event.id,
          scope: "single",
          start_date: recurring_event.start_time.iso8601
        }
      end.to change { recurring_event.reload.recurrence_rule }.to include("EXDATE")
    end

    it "deletes entire series" do
      delete :delete_with_scope, params: {
        id: recurring_event.id,
        scope: "all"
      }

      expect(Event.exists?(recurring_event.id)).to be_falsey
    end

    it "limits recurrence by adjusting UNTIL for 'following'" do
      delete :delete_with_scope, params: {
        id: recurring_event.id,
        scope: "following",
        start_date: recurring_event.start_time.iso8601
      }

      expect(recurring_event.reload.recurrence_rule).to include("UNTIL=")
    end
  end

  describe "GET #json" do
    it "returns event data grouped by type" do
      event
      get :json, params: { id: space.id }

      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first["events"].first["title"]).to eq(event.title)
    end

    # it "returns bad request if id is missing" do
    #   get :json
    #   expect(response).to have_http_status(:bad_request)
    # end
  end

  # describe "POST #publish" do
  #   it "publishes a single event" do
  #     event.update!(draft: true)
  #     post :publish, params: { id: event.id }

  #     expect(event.reload.draft).to be_falsey
  #   end

  #   it "publishes events in a range" do
  #     draft_event = create(:event, space: space, created_by: admin_user, draft: true,
  #       start_time: 2.days.from_now)

  #     post :publish, params: {
  #       view_start_date: 1.day.from_now.to_s,
  #       view_end_date: 3.days.from_now.to_s,
  #       space_id: space.id
  #     }

  #     expect(draft_event.reload.draft).to be_falsey
  #   end
  # end

  describe "DELETE #delete_drafts" do
    it "deletes draft events in a time range" do
      create(:event, space: space, created_by: admin_user, draft: true,
        start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour, recurrence_rule: "")

      expect do
        delete :delete_drafts, params: {
          view_start_date: 1.day.from_now.to_s,
          view_end_date: 3.days.from_now.to_s,
          space_id: space.id
        }
      end.to change(Event, :count).by(-1)
    end
  end

  describe "POST #copy" do
    it "copies non-recurring events as drafts" do
      create(:event, space: space, created_by: admin_user, draft: false,
        start_time: Date.parse("2024-01-01").midnight + 9.hours,
        end_time: Date.parse("2024-01-01").midnight + 11.hours)

      post :copy, params: {
        source_range: "2024-01-01 to 2024-01-01",
        target_date: "2024-02-01",
        space_id: space.id
      }

      expect(Event.where(draft: true).count).to eq(1)
      expect(Event.last.start_time.to_date).to eq(Date.parse("2024-02-01"))
    end
  end
end
