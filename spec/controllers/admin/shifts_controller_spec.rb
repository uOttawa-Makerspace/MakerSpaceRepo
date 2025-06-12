require "rails_helper"

RSpec.describe Admin::EventsController, type: :controller do
  before(:all) { @admin = create(:user, :admin) }

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  # Add this factory definition if you don't have it in your factories file
  FactoryBot.define do
    factory :event do
      title { "Test Event" }
      description { "Test Description" }
      start_time { 1.day.from_now }
      end_time { 1.day.from_now + 2.hours }
      event_type { "meeting" }
      space
      created_by { @admin }
      draft { false }

      trait :recurring do
        recurrence_rule { "RRULE:FREQ=WEEKLY;COUNT=5" }
      end
    end
  end

  describe "GET /index" do
    context "logged as regular user" do
      it "should redirect to root" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return success" do
        Space.find_or_create_by(name: "Makerspace")
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /create" do
    let(:space) { create(:space) }
    let(:staff_members) { create_list(:user, 2, :staff) }
    let(:valid_params) do
      {
        event: {
          title: "Team Meeting",
          description: "Weekly sync",
          utc_start_time: 1.day.from_now.iso8601,
          utc_end_time: (1.day.from_now + 2.hours).iso8601,
          event_type: "meeting",
          space_id: space.id
        },
        staff_select: staff_members.map(&:id)
      }
    end

    context "with valid parameters" do
      it "creates a new event" do
        expect do
          post :create, params: valid_params
        end.to change(Event, :count).by(1)
      end

      it "creates event assignments" do
        post :create, params: valid_params
        event = Event.last
        expect(event.event_assignments.count).to eq(2)
      end

      it "sets default title when blank" do
        post :create, params: valid_params.deep_merge(event: { title: "" })
        expect(Event.last.title).to eq("Meeting")
      end

      it "redirects with success notice" do
        post :create, params: valid_params
        expect(response).to redirect_to(admin_calendar_index_path)
        expect(flash[:notice]).to eq("Event created successfully.")
      end
    end

    context "with invalid parameters" do
      it "does not create event" do
        expect do
          post :create, params: valid_params.deep_merge(event: { space_id: nil })
        end.not_to change(Event, :count)
      end

      it "redirects with error message" do
        post :create, params: valid_params.deep_merge(event: { space_id: nil })
        expect(response).to redirect_to(admin_calendar_index_path)
        expect(flash[:alert]).to include("Failed to create event")
      end
    end
  end

  describe "PATCH /update" do
    let(:space) { create(:space) }
    let(:event) { create(:event, space: space, created_by: @admin) }
    let(:staff_members) { create_list(:user, 2, :staff) }
    let(:update_params) do
      {
        id: event.id,
        event: {
          title: "Updated Title",
          description: "Updated description",
          utc_start_time: 2.days.from_now.iso8601,
          utc_end_time: (2.days.from_now + 2.hours).iso8601,
          event_type: "training",
          space_id: space.id
        },
        staff_select: staff_members.map(&:id)
      }
    end

    context "for non-recurring event" do
      it "updates the event" do
        patch :update, params: update_params
        event.reload
        expect(event.title).to eq("Updated Title")
      end

      it "updates event assignments" do
        patch :update, params: update_params
        expect(event.reload.event_assignments.count).to eq(2)
      end

      it "redirects with success notice" do
        patch :update, params: update_params
        expect(response).to redirect_to(admin_calendar_index_path)
        expect(flash[:notice]).to eq("Event updated successfully.")
      end
    end

    context "for recurring event" do
      let(:event) { create(:event, :recurring, space: space, created_by: @admin) }

      it "handles 'all' scope update" do
        patch :update, params: update_params.merge(update_scope: "all")
        expect(response).to redirect_to(admin_calendar_index_path)
        expect(flash[:notice]).to eq("Unavailability updated successfully.")
      end

      it "handles 'this' scope update" do
        expect do
          patch :update, params: update_params.merge(update_scope: "this")
        end.to change(Event, :count).by(1)
      end
    end
  end

  describe "DELETE /delete_with_scope" do
    let(:space) { create(:space) }
    let(:event) { create(:event, space: space, created_by: @admin) }

    context "for non-recurring event" do
      it "deletes the event" do
        delete :delete_with_scope, params: { id: event.id }
        expect(Event.exists?(event.id)).to be_falsey
      end
    end

    context "for recurring event" do
      let(:event) { create(:event, :recurring, space: space, created_by: @admin) }

      it "handles 'single' scope" do
        delete :delete_with_scope, params: { 
          id: event.id, 
          scope: "single", 
          start_date: event.start_time.iso8601 
        }
        expect(event.reload.recurrence_rule).to include("EXDATE")
      end

      it "handles 'all' scope" do
        delete :delete_with_scope, params: { id: event.id, scope: "all" }
        expect(Event.exists?(event.id)).to be_falsey
      end
    end
  end

  describe "GET /json" do
    let(:space) { create(:space) }

    before do
      # Add route if not already defined in config/routes.rb
      # get 'admin/events/json', to: 'admin/events#json'
    end

    it "returns events for space" do
      create(:event, space: space)
      get :json, params: { id: space.id }
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response).not_to be_empty
    end

    it "returns error without space id" do
      get :json, params: { id: nil }
      expect(response).to have_http_status(:bad_request)
    end

    it "filters out old non-recurring events" do
      old_event = create(:event, space: space, start_time: 3.months.ago, end_time: 3.months.ago)
      get :json, params: { id: space.id }
      json_response = JSON.parse(response.body)
      event_ids = json_response.flat_map { |source| source["events"] }.compact.map { |e| e["id"] }
      expect(event_ids).not_to include("event-#{old_event.id}")
    end
  end

  describe "POST /publish" do
    let(:space) { create(:space) }
    let(:draft_event) { create(:event, space: space, draft: true) }

    it "publishes single event" do
      post :publish, params: { id: draft_event.id }
      expect(draft_event.reload.draft).to be_falsey
    end

    it "publishes multiple events in range" do
      create_list(:event, 2, space: space, draft: true, 
                 start_time: 1.day.from_now, end_time: 2.days.from_now)
      expect do
        post :publish, params: { 
          view_start_date: Time.current.iso8601,
          view_end_date: 3.days.from_now.iso8601,
          space_id: space.id
        }
      end.to change { Event.where(draft: false).count }.by(2)
    end
  end

  describe "DELETE /delete_drafts" do
    let(:space) { create(:space) }

    it "deletes draft events in range" do
      create_list(:event, 2, space: space, draft: true, 
                 start_time: 1.day.from_now, end_time: 2.days.from_now)
      expect do
        delete :delete_drafts, params: { 
          view_start_date: Time.current.iso8601,
          view_end_date: 3.days.from_now.iso8601,
          space_id: space.id
        }
      end.to change(Event, :count).by(-2)
    end

    it "does not delete recurring events" do
      create(:event, :recurring, space: space, draft: true)
      expect do
        delete :delete_drafts, params: { 
          view_start_date: Time.current.iso8601,
          view_end_date: 3.days.from_now.iso8601,
          space_id: space.id
        }
      end.not_to change(Event, :count)
    end
  end

  describe "POST /copy" do
    let(:space) { create(:space) }

    it "copies events to new date" do
      create(:event, space: space, draft: false)
      post :copy, params: { 
        source_range: "#{1.day.from_now.to_date} to #{2.days.from_now.to_date}",
        target_date: 1.week.from_now.to_date,
        space_id: space.id
      }
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:notice]).to include("copied to")
    end

    it "does not copy recurring events" do
      create(:event, :recurring, space: space)
      expect do
        post :copy, params: { 
          source_range: "#{1.day.from_now.to_date} to #{2.days.from_now.to_date}",
          target_date: 1.week.from_now.to_date,
          space_id: space.id
        }
      end.not_to change(Event, :count)
    end
  end
end