# frozen_string_literal: true

require "rails_helper"

# Every admin action that saves or destroys a published event queues exactly one Google job, after the database
# work is done. A failed save queues nothing, and Google is never called from the request.
RSpec.describe "Admin::EventsController Google Calendar jobs", type: :request do
  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }
  let(:calendar_id) { "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" }
  let(:series_rule) { "DTSTART:20250505T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=5" }

  # Published events: a new Event is a draft by default, and the admin form does not send the flag.
  def create_events_as_published
    allow(Event).to receive(:new).and_wrap_original { |original, *args| original.call(*args).tap { |e| e.draft = false } }
  end

  def log_in!
    post login_authentication_path, params: { username_email: admin.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  before do
    log_in! unless RSpec.current_example.metadata[:late_login]
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_raise("Google must not be called")
  end

  def event_attrs(overrides = {})
    { event_type: "meeting", title: "Titled", description: "Desc", space_id: space.id,
      utc_start_time: "2027-04-01 10:00", utc_end_time: "2027-04-01 11:00" }.merge(overrides)
  end

  def push_jobs = enqueued_jobs_of(GoogleCalendar::EventPushJob)
  def delete_jobs = enqueued_jobs_of(GoogleCalendar::EventDeleteJob)

  def enqueued_jobs_of(klass)
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == klass }
  end

  describe "POST create" do
    it "queues one push with a Google id already stored, and never inserts into Google from the request" do
      create_events_as_published
      expect { post admin_events_path, params: { event: event_attrs } }.to change(Event, :count).by(1)
      event = Event.order(:id).last
      expect(event.draft).to be(false)
      expect(event.google_event_id).to match(/\A[0-9a-v]{32}\z/)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(event.id).exactly(:once)
      expect(push_jobs.size).to eq(1)
    end

    it "queues nothing when the event is invalid" do
      post admin_events_path, params: { event: event_attrs(utc_end_time: "2027-04-01 09:00") }
      expect(push_jobs).to be_empty
    end

    it "queues nothing for a draft" do
      post admin_events_path, params: { event: event_attrs }
      expect(Event.order(:id).last.draft).to be(true)
      expect(push_jobs).to be_empty
    end
  end

  describe "creating an event end to end" do
    include ActiveJob::TestHelper

    it "inserts the new event into Google exactly once, with the id stored on the row" do
      create_events_as_published
      service = instance_double(Google::Apis::CalendarV3::CalendarService, "authorization=": nil)
      allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
      inserted = []
      allow(service).to receive(:update_event).and_raise(Google::Apis::ClientError.new("missing", status_code: 404))
      allow(service).to receive(:insert_event) { |cal, gcal| inserted << [cal, gcal.id] }

      post admin_events_path, params: { event: event_attrs }
      perform_enqueued_jobs

      event = Event.order(:id).last
      expect(inserted).to eq([[calendar_id, event.google_event_id]])
    end
  end

  describe "PATCH update" do
    it "queues one push for a non-recurring update" do
      event = create(:event, space: space, google_event_id: "g1")
      patch admin_event_path(event), params: { event: event_attrs }
      expect(push_jobs.size).to eq(1)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(event.id)
    end

    it "queues one push when the event moves to another space (the job moves the Google copy)" do
      mtc = create(:space, name: "MTC")
      event = create(:event, space: space, google_event_id: "g1", google_calendar_id: calendar_id)
      patch admin_event_path(event), params: { event: event_attrs(space_id: mtc.id) }
      expect(event.reload.space_id).to eq(mtc.id)
      expect(push_jobs.size).to eq(1)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(event.id)
      expect(delete_jobs).to be_empty
    end

    it "queues nothing when the update is invalid" do
      event = create(:event, space: space)
      patch admin_event_path(event), params: { event: event_attrs(utc_end_time: "2027-04-01 09:00") }
      expect(push_jobs).to be_empty
    end

    it "queues one push of the series for scope all" do
      series = create(:event, space: space, recurrence_rule: series_rule, google_event_id: "g1",
                              start_time: Time.utc(2025, 5, 5, 15), end_time: Time.utc(2025, 5, 5, 16))
      patch admin_event_path(series), params: { update_scope: "all", event: event_attrs(
        utc_start_time: "2025-05-12 17:00", utc_end_time: "2025-05-12 18:00", recurrence_rule: series_rule) }
      expect(push_jobs.size).to eq(1)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(series.id)
    end

    it "queues a push of the series and of the new occurrence for scope this" do
      create_events_as_published
      series = create(:event, space: space, recurrence_rule: series_rule, google_event_id: "g1",
                              start_time: Time.utc(2025, 5, 5, 15), end_time: Time.utc(2025, 5, 5, 16))
      patch admin_event_path(series), params: { update_scope: "this", event: event_attrs(
        utc_start_time: "2025-05-12 17:00", utc_end_time: "2025-05-12 18:00") }
      replacement = Event.order(:id).last
      expect(replacement.id).not_to eq(series.id)
      expect(push_jobs.size).to eq(2)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(series.id).exactly(:once)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(replacement.id).exactly(:once)
    end

    it "queues only the series push for scope this when the replacement is a draft" do
      series = create(:event, space: space, recurrence_rule: series_rule, google_event_id: "g1",
                              start_time: Time.utc(2025, 5, 5, 15), end_time: Time.utc(2025, 5, 5, 16))
      patch admin_event_path(series), params: { update_scope: "this", event: event_attrs(
        utc_start_time: "2025-05-12 17:00", utc_end_time: "2025-05-12 18:00") }
      expect(push_jobs.size).to eq(1)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(series.id)
    end

    it "queues nothing for scope this when the replacement is invalid" do
      series = create(:event, space: space, recurrence_rule: series_rule)
      patch admin_event_path(series), params: { update_scope: "this", event: event_attrs(
        utc_start_time: "2025-05-12 18:00", utc_end_time: "2025-05-12 17:00") }
      expect(push_jobs).to be_empty
    end
  end

  describe "DELETE delete_with_scope" do
    let(:series) do
      create(:event, space: space, recurrence_rule: series_rule, google_event_id: "g1",
                     start_time: Time.utc(2025, 5, 5, 15), end_time: Time.utc(2025, 5, 5, 16))
    end

    it "removes the copy from the calendar that really holds it when a move is still pending" do
      mtc = create(:space, name: "MTC")
      event = create(:event, space: mtc, google_event_id: "g1", google_calendar_id: calendar_id)
      delete delete_with_scope_admin_event_path(event)
      expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued.with("g1", calendar_id, event.id).exactly(:once)
    end

    it "queues the removal of a destroyed event's Google copy with the ids captured before the destroy" do
      event = create(:event, space: space, google_event_id: "g1")
      expect { delete delete_with_scope_admin_event_path(event) }.to change(Event, :count).by(-1)
      expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued.with("g1", calendar_id, event.id).exactly(:once)
      expect(push_jobs).to be_empty
    end

    it "queues the removal of a destroyed draft that has a Google id" do
      draft = create(:event, :draft, space: space, google_event_id: "g2")
      delete delete_with_scope_admin_event_path(draft)
      expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued.with("g2", calendar_id, draft.id)
    end

    it "queues no removal for an event never pushed" do
      event = create(:event, space: space, google_event_id: nil)
      delete delete_with_scope_admin_event_path(event)
      expect(delete_jobs).to be_empty
    end

    it "removes the whole series for scope all" do
      delete delete_with_scope_admin_event_path(series), params: { scope: "all" }
      expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued.with("g1", calendar_id, series.id).exactly(:once)
    end

    %w[single following].each do |scope|
      it "queues one push of the series for scope #{scope}" do
        delete delete_with_scope_admin_event_path(series), params: { scope: scope, start_date: "2025-05-19 15:00" }
        expect(push_jobs.size).to eq(1)
        expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(series.id)
        expect(delete_jobs).to be_empty
      end
    end

    it "queues nothing for an invalid scope" do
      delete delete_with_scope_admin_event_path(series), params: { scope: "bogus" }
      expect(push_jobs + delete_jobs).to be_empty
    end
  end

  describe "PATCH publish" do
    it "queues one push when a draft is published" do
      draft = create(:event, :draft, space: space)
      patch publish_admin_events_path, params: { id: draft.id }
      expect(draft.reload.draft).to be(false)
      expect(push_jobs.size).to eq(1)
      expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(draft.id)
    end

    it "queues one push per draft published in the range, and none for a draft that fails", :late_login do
      travel_to(Time.zone.local(2027, 4, 1, 18, 0)) do
        log_in!
        ok = create(:event, :draft, space: space)
        bad = create(:event, :draft, :training, space: space, training: nil)
        bad.update_columns(training_id: nil)
        patch publish_admin_events_path, params: { space_id: space.id, view_start_date: "2027-03-31", view_end_date: "2027-04-02" }
        expect(GoogleCalendar::EventPushJob).to have_been_enqueued.with(ok.id).exactly(:once)
        expect(GoogleCalendar::EventPushJob).not_to have_been_enqueued.with(bad.id)
        expect(push_jobs.size).to eq(1)
      end
    end
  end

  describe "DELETE delete_drafts" do
    it "queues one removal per destroyed draft that has a Google id", :late_login do
      travel_to(Time.zone.local(2027, 4, 1, 18, 0)) do
        log_in!
        with_id = create(:event, :draft, space: space, google_event_id: "g3")
        create(:event, :draft, space: space, google_event_id: nil)
        delete delete_drafts_admin_events_path, params: { space_id: space.id, view_start_date: "2027-03-31", view_end_date: "2027-04-02" }
        expect(Event.exists?(with_id.id)).to be(false)
        expect(delete_jobs.size).to eq(1)
        expect(GoogleCalendar::EventDeleteJob).to have_been_enqueued.with("g3", calendar_id, with_id.id)
      end
    end
  end

  describe "POST copy" do
    it "queues nothing: copies are drafts" do
      create(:event, space: space, start_time: Time.utc(2027, 4, 5, 14), end_time: Time.utc(2027, 4, 5, 15))
      post copy_admin_events_path, params: { space_id: space.id, source_range: "2027-04-05 to 2027-04-11", target_date: "2027-05-03" }
      expect(Event.where(draft: true).count).to eq(1)
      expect(push_jobs + delete_jobs).to be_empty
    end

    it "gives the copy of a published event no Google ids, as for any event not yet in Google" do
      create(:event, space: space, start_time: Time.utc(2027, 4, 5, 14), end_time: Time.utc(2027, 4, 5, 15),
                     google_event_id: "g1", google_calendar_id: calendar_id)
      post copy_admin_events_path, params: { space_id: space.id, source_range: "2027-04-05 to 2027-04-11", target_date: "2027-05-03" }
      copy = Event.find_by!(draft: true)
      expect(copy.google_event_id).to be_nil
      expect(copy.google_calendar_id).to be_nil
    end
  end
end
