class ShadowingHour < ApplicationRecord
  include DisplayUser
  belongs_to :user, optional: true
  belongs_to :space, optional: true
  display_user_for :user

  # Statuses Google answers when the event a delete asks for is already gone.
  GONE_STATUSES = [404, 410].freeze
  # What Google answers when an event is created under an id it already has.
  ALREADY_EXISTS_STATUS = 409

  # The columns allow NULL and older rows may lack a time, so those rows stay
  # editable for other fields: both times are required for a new row, or when
  # either time is being changed.
  validates :start_time, :end_time, presence: true, if: :times_required?

  # Rows with both times stored; the only ones that can be shown as a shift.
  scope :complete, -> { where.not(start_time: nil).where.not(end_time: nil) }

  def self.authorizer
    scope = "https://www.googleapis.com/auth/calendar"

    @config = {
      private_key:
        Rails.application.credentials[Rails.env.to_sym][:google][:private_key],
      client_email:
        Rails.application.credentials[Rails.env.to_sym][:google][:client_email],
      project_id:
        Rails.application.credentials[Rails.env.to_sym][:google][:project_id],
      private_key_id:
        Rails.application.credentials[Rails.env.to_sym][:google][
          :private_key_id
        ],
      type: Rails.application.credentials[Rails.env.to_sym][:google][:type]
    }

    authorizer =
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(@config.to_json, "r"),
        scope: scope
      )

    authorizer.sub = "volunteer@makerepo.com"

    authorizer.fetch_access_token!

    return authorizer
  end

  # Creates the shift's Google event under the shift's own event_id, so doing it again cannot make a second one:
  # an event that already exists (409) counts as created. Any other failure is raised, for the job to retry or
  # report. An event Google reports cancelled was removed by hand; it is reported once and not retried.
  def publish_to_calendar
    return unless calendar_ready?

    event = self.class.create_event(calendar_time(start_time), calendar_time(end_time), user, space.name.downcase, event_id)
    report_cancelled if event.status == "cancelled"
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == ALREADY_EXISTS_STATUS
  end

  # +event_id+ is the id the Google event is created with, so a repeated call cannot create a second event.
  def self.create_event(start_time, end_time, user, space, event_id = nil)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    attendees =
      (
        if !Rails.env.test?
          [Google::Apis::CalendarV3::EventAttendee.new(email: user.email)]
        else
          []
        end
      )

    event =
      Google::Apis::CalendarV3::Event.new(
        id: event_id,
        summary: "#{user.name} Shadowing",
        start:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: start_time,
            time_zone: "America/Toronto"
          ),
        end:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: end_time,
            time_zone: "America/Toronto"
          ),
        attendees: attendees
      )

    calendar_id =
      (
        if space == "makerspace"
          Rails.application.credentials[Rails.env.to_sym][:calendar][
            :makerspace
          ]
        else
          Rails.application.credentials[Rails.env.to_sym][:calendar][
            :brunsfield
          ]
        end
      )

    response =
      service.insert_event(calendar_id, event, send_notifications: true)

    return response
  end

  def self.delete_event(event_id, space)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    calendar_id =
      (
        if space == "Makerspace"
          Rails.application.credentials[Rails.env.to_sym][:calendar][
            :makerspace
          ]
        else
          Rails.application.credentials[Rails.env.to_sym][:calendar][
            :brunsfield
          ]
        end
      )

    begin
      response = service.delete_event(calendar_id, event_id)
    rescue Google::Apis::ClientError => error
      return response if already_gone?(error)

      HandledError.report(error, source: "shadowing_hour.delete_event", event_id: event_id)
      return "error"
    rescue StandardError => error
      HandledError.report(error, source: "shadowing_hour.delete_event", event_id: event_id)
      return "error"
    end

    return response
  end

  # Google no longer has the event, which is what a delete wants.
  def self.already_gone?(error)
    error.to_s.include?("Resource has been deleted") || GONE_STATUSES.include?(error.status_code)
  end
  private_class_method :already_gone?

  private

  # An older row can lack its volunteer, space or times; there is nothing to put on the calendar for it.
  def calendar_ready?
    user && space && start_time && end_time
  end

  def report_cancelled
    HandledError.report(RuntimeError.new("Google Calendar reports the shadowing shift's event cancelled"),
                        source: "shadowing_hour.publish_to_calendar", shadowing_hour_id: id)
  end

  # The calendar's timestamp for a stored time, in the application's (Eastern) time.
  def calendar_time(time)
    time.in_time_zone.strftime("%Y-%m-%dT%H:%M:00")
  end

  def times_required?
    new_record? || start_time_changed? || end_time_changed?
  end
end
