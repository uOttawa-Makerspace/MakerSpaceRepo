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

  def self.authorizer = GoogleCalendar::ServiceAccount.authorizer

  # Creates the shift's Google event under the shift's own event_id, so doing it again cannot make a second one.
  # Google keeps the id of a deleted event reserved, so an id that already exists (409) is either the event
  # or one removed by hand: the event is read, and one found cancelled is reported once and not retried. Any
  # other failure is raised, for the job to retry or report.
  # Runs under the shift's row lock, so cancelling the shift cannot slip in between the shift being read and
  # its event being created (which would leave an event nothing removes). Does nothing for a shift that is gone.
  def publish_to_calendar
    self.class.transaction do
      locked = self.class.lock.find_by(id: id)
      locked&.create_calendar_event
    end
  end

  # Removes the shift's Google event, then the shift, under the same row lock. Answers :removed, :gone (the shift
  # was already cancelled) or :not_removed (Google did not confirm the removal: the shift is kept).
  def cancel
    self.class.transaction do
      locked = self.class.lock.find_by(id: id)
      next :gone unless locked
      next :not_removed if self.class.delete_event(locked.event_id, locked.space.name) == "error"

      locked.destroy!
      :removed
    end
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

  # The Google event with this id, in the calendar of the space (a name, any case).
  def self.get_event(event_id, space)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    calendars = Rails.application.credentials[Rails.env.to_sym][:calendar]
    service.get_event(space.downcase == "makerspace" ? calendars[:makerspace] : calendars[:brunsfield], event_id)
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

  protected

  def create_calendar_event
    return unless calendar_ready?

    self.class.create_event(calendar_time(start_time), calendar_time(end_time), user, space.name.downcase, event_id)
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == ALREADY_EXISTS_STATUS

    report_cancelled if self.class.get_event(event_id, space.name).status == "cancelled"
  end

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
