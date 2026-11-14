# frozen_string_literal: true

require "rails_helper"

# The admin calendar's event feed (GET json) and the publish action, pinned as whole responses: the feed's JSON
# is compared character for character (key order, number format and all), and publish by what it saved, what it
# left alone, the messages it answered with and the Google pushes it queued.
RSpec.describe "Admin events feed and publish", type: :request do
  let(:zone) { ActiveSupport::TimeZone["America/Toronto"] }
  let(:space) { create(:space) }
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  def push_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == GoogleCalendar::EventPushJob }
  end

  def pushed_ids = push_jobs.map { |job| job[:args].first }

  describe "GET json" do
    let(:alice) { create(:user, :staff, name: "Alice Shift") }
    let(:bruno) { create(:user, :staff, name: "Bruno Shift") }
    let(:cara) { create(:user, :staff, name: "Cara Train") }
    let(:training) { create(:training, name_en: "Laser Cutting", name_fr: "Decoupe laser") }
    let(:course) { create(:course_name, name: "MCG 1101") }

    let!(:shift) do
      create(:event, space: space, created_by: admin, event_type: "shift", title: "Shift", description: "Front desk",
                     start_time: zone.local(2027, 3, 13, 22), end_time: zone.local(2027, 3, 14, 4))
    end
    let!(:lesson) do
      create(:event, :draft, space: space, created_by: admin, event_type: "training", title: "Training", training: training,
                             course_name: course, language: "English", description: "Bring goggles",
                             start_time: zone.local(2027, 3, 16, 9), end_time: zone.local(2027, 3, 16, 11))
    end
    let!(:sync) do
      create(:event, space: space, created_by: admin, event_type: "meeting", title: "Weekly sync", description: "Agenda",
                     start_time: Time.utc(2027, 3, 8, 14), end_time: Time.utc(2027, 3, 8, 15, 30),
                     recurrence_rule: "DTSTART:20270308T140000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4")
    end
    let!(:open_hours) do
      create(:event, :draft, space: space, created_by: admin, event_type: "other", title: "Open hours", description: nil,
                             start_time: zone.local(2027, 3, 12, 10), end_time: zone.local(2027, 3, 12, 12),
                             recurrence_rule: "RRULE:FREQ=DAILY;COUNT=3")
    end
    let!(:holiday) do
      create(:event, space: space, created_by: admin, event_type: "other", title: "Holiday", description: nil,
                     start_time: zone.local(2027, 3, 17), end_time: zone.local(2027, 3, 18))
    end

    before do
      create(:staff_space, user: alice, space: space, color: "#ff0000")
      create(:staff_space, user: bruno, space: space, color: "#00aa00")
      create(:event_assignment, event: shift, user: alice)
      create(:event_assignment, event: shift, user: bruno)
      create(:event_assignment, event: lesson, user: cara)
      create(:event, space: create(:space), created_by: admin, title: "Elsewhere")
      log_in!(admin)
    end

    def unassigned = [{ id: 0, name: "Unassigned" }]

    def shift_row
      { id: "event-#{shift.id}", title: "Shift for Alice Shift, Bruno Shift",
        start: "2027-03-13T22:00:00-05:00", end: "2027-03-14T04:00:00-04:00", allDay: false,
        extendedProps: { name: "Shift", draft: false, description: "Front desk", eventType: "shift", trainingId: nil,
                         language: nil, course_name: nil,
                         assignedUsers: [{ id: alice.id, name: "Alice Shift" }, { id: bruno.id, name: "Bruno Shift" }],
                         background: "linear-gradient(to right, #ff0000 0.0%, #ff0000 50.0%, #00aa00 50.0%, #00aa00 100.0%);" } }
    end

    def lesson_row
      { id: "event-#{lesson.id}", title: "✎ Laser Cutting (MCG 1101 - English) for Cara Train",
        start: "2027-03-16T09:00:00-04:00", end: "2027-03-16T11:00:00-04:00", allDay: false,
        extendedProps: { name: "Training", draft: true, description: "Bring goggles", eventType: "training",
                         trainingId: training.id, language: "English", course_name: CourseName.find(course.id).as_json,
                         assignedUsers: [{ id: cara.id, name: "Cara Train" }],
                         background: "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%); opacity: 0.8;" } }
    end

    def sync_row
      { id: "event-#{sync.id}", title: "Weekly sync", start: "2027-03-08T09:00:00-05:00", end: "2027-03-08T10:30:00-05:00",
        rrule: "DTSTART:20270308T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4", duration: 5_400_000.0,
        allDay: false,
        extendedProps: { name: "Meeting", draft: false, description: "Agenda", eventType: "meeting", trainingId: nil,
                         language: nil, course_name: nil, assignedUsers: unassigned,
                         background: "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);" } }
    end

    def open_hours_row
      { id: "event-#{open_hours.id}", title: "✎ Open hours", start: "2027-03-12T10:00:00-05:00",
        end: "2027-03-12T12:00:00-05:00",
        rrule: "DTSTART:20270312T100000\nRRULE:FREQ=DAILY;COUNT=3", duration: 7_200_000.0,
        allDay: false,
        extendedProps: { name: "Other", draft: true, description: nil, eventType: "other", trainingId: nil,
                         language: nil, course_name: nil, assignedUsers: unassigned,
                         background: "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%); opacity: 0.8;" } }
    end

    def holiday_row
      { id: "event-#{holiday.id}", title: "Holiday", start: "2027-03-17T00:00:00-04:00", end: "2027-03-18T00:00:00-04:00",
        allDay: true,
        extendedProps: { name: "Other", draft: false, description: nil, eventType: "other", trainingId: nil,
                         language: nil, course_name: nil, assignedUsers: unassigned,
                         background: "linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);" } }
    end

    # The body with its groups and rows put in id order (the feed's own order is the database's), written back
    # out as JSON so key order and number format are compared too.
    def sorted_body
      JSON.parse(response.body).sort_by { |group| group["id"] }
          .map { |group| group.merge("events" => group["events"].sort_by { |row| row["id"] }) }.to_json
    end

    def expected(groups)
      groups.sort_by { |id, _| id }.map { |id, rows| { id: id, events: rows.sort_by { |row| row[:id] } } }.to_json
    end

    it "answers every event of the space, grouped by type, each row exactly as the calendar reads it" do
      get json_admin_events_path(id: space.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(sorted_body).to eq(expected("shift" => [shift_row], "training" => [lesson_row], "meeting" => [sync_row],
                                         "other" => [open_hours_row, holiday_row]))
    end

    it "keeps the one-offs that overlap the requested range and every series that starts before its end" do
      get json_admin_events_path(id: space.id), params: { start: "2027-03-15T00:00:00", end: "2027-03-16T00:00:00" }

      expect(response).to have_http_status(:ok)
      expect(sorted_body).to eq(expected("meeting" => [sync_row], "other" => [open_hours_row]))
    end

    it "keeps a one-off that ends exactly at the start of the range, read as Toronto wall time" do
      get json_admin_events_path(id: space.id), params: { start: "2027-03-14T04:00:00", end: "2027-03-14T05:00:00" }

      expect(sorted_body).to eq(expected("shift" => [shift_row], "meeting" => [sync_row], "other" => [open_hours_row]))
    end

    it "answers 400 with the reason for a range it cannot read, and for a blank space" do
      get json_admin_events_path(id: space.id), params: { start: "2027-03-15T00:00:00" }
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq({ error: I18n.t("errors.calendar.window_invalid") }.to_json)

      get json_admin_events_path(id: " ")
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to eq('{"error":"Space ID is required"}')
    end

    it "reads the feed in eight queries, one of them the trainings of the training events, read together" do
      count = 0
      counter = lambda do |*, payload|
        count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get json_admin_events_path(id: space.id) }

      expect(response).to have_http_status(:ok)
      expect(count).to eq(8)
    end

    # One training event per day after the 20th, each with its own training, so no read of one is answered from the
    # query cache.
    def titled_lessons!(*days)
      days.map do |i|
        create(:event, space: space, created_by: admin, event_type: "training", title: "Training",
                       training: create(:training, name_en: "Extra #{i}"),
                       start_time: zone.local(2027, 3, 20 + i, 9), end_time: zone.local(2027, 3, 20 + i, 11))
          .tap { |event| create(:event_assignment, event: event, user: cara) }
      end
    end

    it "names the trainings of the training events in a number of queries that does not grow with them", :aggregate_failures do
      titled_lessons!(0)
      get json_admin_events_path(id: space.id) # warm up (caches, constants)
      few = count_queries { get json_admin_events_path(id: space.id) }
      extra = titled_lessons!(1, 2, 3)
      many = count_queries { get json_admin_events_path(id: space.id) }

      expect(many).to eq(few)
      titles = response.parsed_body.find { |group| group["id"] == "training" }["events"].to_h { |row| [row["id"], row["title"]] }
      expect(extra.map { |event| titles["event-#{event.id}"] }).to eq(["Extra 1", "Extra 2", "Extra 3"].map { |name| "#{name} for Cara Train" })
    end
  end

  it "answers a single unassigned event as this exact body" do
    event = create(:event, space: space, created_by: admin, event_type: "meeting", title: "Board", description: "Q2",
                           start_time: Time.utc(2027, 4, 1, 14), end_time: Time.utc(2027, 4, 1, 15))
    log_in!(admin)

    get json_admin_events_path(id: space.id)

    expect(response.body).to eq(
      '[{"id":"meeting","events":[{"id":"event-' + event.id.to_s + '","title":"Board","start":"2027-04-01T10:00:00-04:00",' \
      '"end":"2027-04-01T11:00:00-04:00","allDay":false,"extendedProps":{"name":"Meeting","draft":false,"description":"Q2",' \
      '"eventType":"meeting","trainingId":null,"language":null,"course_name":null,' \
      '"assignedUsers":[{"id":0,"name":"Unassigned"}],"background":"linear-gradient(to right, #bbb 0.0%, #bbb 100.0%);"}}]}]'
    )
  end

  it "colours an assignee without a colour in the space grey, and an assignment without a user with no id or name" do
    event = create(:event, space: space, created_by: admin, title: "Meeting", event_type: "meeting",
                           start_time: Time.utc(2027, 4, 1, 14), end_time: Time.utc(2027, 4, 1, 15))
    coloured = create(:user, :staff, name: "Dana Colour")
    create(:staff_space, user: coloured, space: space, color: "#123456")
    create(:event_assignment, event: event, user: coloured)
    create(:event_assignment, event: event).update_column(:user_id, nil)
    log_in!(admin)

    get json_admin_events_path(id: space.id)

    props = response.parsed_body.first["events"].first["extendedProps"]
    expect(props["assignedUsers"]).to eq([{ "id" => coloured.id, "name" => "Dana Colour" }, { "id" => nil, "name" => nil }])
    expect(props["background"]).to eq("linear-gradient(to right, #123456 0.0%, #123456 50.0%, #bbb 50.0%, #bbb 100.0%);")
  end

  describe "PATCH publish for the shown range" do
    let(:referer) { "http://www.example.com/admin/calendar?space=#{space.id}" }
    let(:range) { { space_id: space.id, view_start_date: "2027-03-31", view_end_date: "2027-04-02" } }

    def publish_range(params = range) = patch(publish_admin_events_path, params: params, headers: { "HTTP_REFERER" => referer })

    it "publishes the space's drafts that start in the range, pushes each, and leaves everything else as it was" do
      travel_to(zone.local(2027, 4, 1, 18)) do
        single = create(:event, :draft, space: space, start_time: zone.local(2027, 3, 31, 9), end_time: zone.local(2027, 3, 31, 10))
        series = create(:event, :draft, :recurring_daily, space: space,
                                                          start_time: zone.local(2027, 4, 1, 9), end_time: zone.local(2027, 4, 1, 10))
        at_end = create(:event, :draft, space: space, start_time: zone.local(2027, 4, 2), end_time: zone.local(2027, 4, 2, 1))
        after_end = create(:event, :draft, space: space, start_time: zone.local(2027, 4, 2, 0, 1),
                                           end_time: zone.local(2027, 4, 2, 1))
        before_start = create(:event, :draft, space: space, start_time: zone.local(2027, 3, 30, 23, 59),
                                              end_time: zone.local(2027, 3, 31, 1))
        elsewhere = create(:event, :draft, start_time: zone.local(2027, 4, 1, 9), end_time: zone.local(2027, 4, 1, 10))
        published = create(:event, space: space, start_time: zone.local(2027, 4, 1, 9), end_time: zone.local(2027, 4, 1, 10))
        failing = create(:event, :draft, space: space, event_type: "training", title: "", training: nil,
                                         start_time: zone.local(2027, 4, 1, 12), end_time: zone.local(2027, 4, 1, 13))
        log_in!(admin)

        publish_range

        expect(response).to redirect_to(referer)
        expect(flash[:notice]).to eq("3 event(s) published.")
        expect(flash[:alert]).to eq("Failed to publish 1 event(s): Event ##{failing.id} (Training This field is required.)")
        [single, series, at_end].each do |event|
          expect(event.reload).to have_attributes(draft: false, updated_by_id: admin.id)
        end
        [after_end, before_start, elsewhere, failing].each do |event|
          expect(event.reload).to have_attributes(draft: true, updated_by_id: nil)
        end
        expect(published.reload.updated_by_id).to be_nil
        expect(pushed_ids).to contain_exactly(single.id, series.id, at_end.id)
      end
    end

    it "names a failing draft by its title and joins several failures in one sentence" do
      travel_to(zone.local(2027, 4, 1, 18)) do
        first = create(:event, :draft, space: space, event_type: "training", title: "Lathe", training: nil,
                                       start_time: zone.local(2027, 4, 1, 9), end_time: zone.local(2027, 4, 1, 10))
        second = create(:event, :draft, space: space, event_type: "training", title: "Mill", training: nil,
                                        start_time: zone.local(2027, 4, 1, 11), end_time: zone.local(2027, 4, 1, 12))
        log_in!(admin)

        publish_range

        expect(flash[:notice]).to eq("0 event(s) published.")
        expect(flash[:alert]).to start_with("Failed to publish 2 event(s): ")
        expect(flash[:alert]).to include("Lathe (Training This field is required.)", "Mill (Training This field is required.)", " and ")
        expect([first, second].map { |event| event.reload.draft }).to eq([true, true])
        expect(push_jobs).to be_empty
      end
    end

    it "answers with a count of zero and no alert when the range holds no drafts" do
      log_in!(admin)

      publish_range

      expect(response).to redirect_to(referer)
      expect(flash[:notice]).to eq("0 event(s) published.")
      expect(flash[:alert]).to be_nil
      expect(push_jobs).to be_empty
    end

    it "falls back to the admin calendar without a referer, and asks for the space before publishing anything" do
      draft = create(:event, :draft, space: space, start_time: zone.local(2027, 4, 1, 9), end_time: zone.local(2027, 4, 1, 10))
      log_in!(admin)

      patch publish_admin_events_path, params: range.except(:space_id)
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:alert]).to eq("Space ID is required.")
      expect(draft.reload.draft).to be(true)

      patch publish_admin_events_path, params: range
      expect(response).to redirect_to(admin_calendar_index_path)
      expect(flash[:notice]).to eq("1 event(s) published.")
    end
  end

  describe "PATCH publish for one event" do
    it "publishes it, records the editor, pushes it and answers the dialog with a stream" do
      event = create(:event, :draft, space: space)
      log_in!(admin)

      patch publish_admin_event_path(event), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Event published successfully.")
      expect(event.reload).to have_attributes(draft: false, updated_by_id: admin.id)
      expect(pushed_ids).to eq([event.id])
    end

    it "publishes an already published event again and pushes it" do
      event = create(:event, space: space)
      log_in!(admin)

      patch publish_admin_event_path(event)

      expect(flash[:notice]).to eq("Event published successfully.")
      expect(event.reload.updated_by_id).to eq(admin.id)
      expect(pushed_ids).to eq([event.id])
    end

    it "leaves an event that cannot be saved a draft, pushes nothing and redirects back with the reason" do
      event = create(:event, :draft, space: space, event_type: "training", training: nil)
      log_in!(admin)

      patch publish_admin_event_path(event), headers: { "HTTP_REFERER" => "http://www.example.com/admin/calendar" }

      expect(response).to redirect_to("http://www.example.com/admin/calendar")
      expect(flash[:alert]).to eq("Failed to publish event: Training This field is required.")
      expect(event.reload).to have_attributes(draft: true, updated_by_id: nil)
      expect(push_jobs).to be_empty
    end

    it "answers 404 for an unknown event" do
      log_in!(admin)

      patch publish_admin_event_path(id: 0)

      expect(response).to have_http_status(:not_found)
    end
  end
end
