# frozen_string_literal: true

module GoogleCalendar
  # Sends Event changes to the space's Google Calendar. Called by the push and delete jobs, never from a model
  # callback.
  #
  # The Google event id is chosen by us (Event#push_to_google_later stores it before the first push). A push
  # updates that id; when Google answers 404 the event is not there yet, so it is inserted with that same id, and a
  # 409 on the insert (another push got there first) is answered with one more update. Retrying a push therefore
  # never creates a second copy.
  class EventPublisher
    CALENDARS = {
      "MTC" => "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com",
      "Makerspace" => "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com"
    }.freeze
    TEST_CALENDAR = "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com"
    CONFLICT = 409
    NOT_FOUND = 404
    GONE = [404, 410].freeze

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

    def push(event)
      calendar_id = self.class.calendar_id_for(event.space)
      gcal_event = EventPayload.new(event).build
      gcal_event.id = event.google_event_id
      begin
        service.update_event(calendar_id, event.google_event_id, gcal_event)
      rescue Google::Apis::ClientError => e
        raise unless e.status_code == NOT_FOUND

        insert(calendar_id, gcal_event)
      end
    end

    # A Google event that is already gone counts as removed.
    def remove(google_event_id, calendar_id)
      service.delete_event(calendar_id, google_event_id)
    rescue Google::Apis::ClientError => e
      raise unless GONE.include?(e.status_code)
    end

    private

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
