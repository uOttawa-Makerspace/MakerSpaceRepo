# frozen_string_literal: true

module GoogleCalendar
  # Sends Event changes to the space's Google Calendar. Called by the push and delete jobs, never from a model
  # callback.
  #
  # The Google event id is chosen by us (Event#push_to_google_later stores it before the first push). A push
  # updates that id. When Google answers 404 (not there yet) the event is inserted with
  # that same id, and a 409 on the insert (another push got there first) is answered with one more update.
  # Retrying a push therefore never creates a second copy.
  class EventPublisher
    CALENDARS = {
      "MTC" => "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com",
      "Makerspace" => "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com"
    }.freeze
    TEST_CALENDAR = "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com"
    CONFLICT = 409
    NOT_FOUND = 404
    GONE = [NOT_FOUND, 410].freeze

    def self.calendar_id_for(space)
      CALENDARS.fetch(space.name, TEST_CALENDAR)
    end

    def self.authorizer
      credentials = Rails.application.credentials[Rails.env.to_sym][:google]
      key = credentials.slice(:private_key, :client_email, :project_id, :private_key_id, :type)
      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(key.to_json, "r"),
        scope: "https://www.googleapis.com/auth/calendar"
      )
      authorizer.sub = "volunteer@makerepo.com"
      authorizer.fetch_access_token!
      authorizer
    end

    def self.service
      Google::Apis::CalendarV3::CalendarService.new.tap { |service| service.authorization = authorizer }
    end

    # Brings the Google copy in line with the event: moves it first if it sits in another calendar than the
    # event's space now calls for (the stored calendar is where it really is), then updates it, or inserts it when
    # Google does not have it. The calendar that holds it is recorded.
    def push(event)
      calendar_id = self.class.calendar_id_for(event.space)
      move_to(event, calendar_id)
      gcal_event = EventPayload.new(event).build
      gcal_event.id = event.google_event_id
      begin
        service.update_event(calendar_id, event.google_event_id, gcal_event)
      rescue Google::Apis::ClientError => e
        raise unless e.status_code == NOT_FOUND

        insert(calendar_id, gcal_event)
      end
      record_calendar(event, calendar_id)
    end

    # A Google event that is already gone counts as removed.
    def remove(google_event_id, calendar_id)
      service.delete_event(calendar_id, google_event_id)
    rescue Google::Apis::ClientError => e
      raise unless GONE.include?(e.status_code)
    end

    private

    # Moving keeps the Google id and leaves no deleted copy behind. A 404 means the event is not in the stored
    # calendar, so the update or insert that follows decides. Any other failure keeps the stored calendar as it
    # is, so the next push tries the move again instead of inserting a second copy.
    def move_to(event, calendar_id)
      from_calendar_id = event.google_calendar_id
      return if from_calendar_id.blank? || from_calendar_id == calendar_id

      service.move_event(from_calendar_id, event.google_event_id, calendar_id)
      record_calendar(event, calendar_id)
    rescue Google::Apis::ClientError => e
      raise unless e.status_code == NOT_FOUND
    end

    # Bookkeeping written by the jobs only, never by a callback: update_column keeps it from validating the event,
    # touching updated_at or running callbacks. It is written after every confirmed change in Google, not compared
    # with the value this run loaded, which another run may have changed since.
    def record_calendar(event, calendar_id)
      event.update_column(:google_calendar_id, calendar_id)
    end

    # The id is not in Google yet. A 409 means another push inserted it first, so update it once.
    def insert(calendar_id, gcal_event)
      service.insert_event(calendar_id, gcal_event)
    rescue Google::Apis::ClientError => e
      raise unless e.status_code == CONFLICT

      service.update_event(calendar_id, gcal_event.id, gcal_event)
    end

    def service
      @service ||= self.class.service
    end
  end
end
