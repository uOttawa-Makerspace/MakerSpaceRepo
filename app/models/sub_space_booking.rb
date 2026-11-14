class SubSpaceBooking < ApplicationRecord
  include DisplayUser

  belongs_to :user, optional: true
  display_user_for :user
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :sub_space
  belongs_to :recurring_booking, optional: true
  # A new booking must be saved with a status (see save_with_status!). Optional on the association
  # because the column may still be empty on rows older than the status column.
  belongs_to :booking_status, optional: true
  validates :booking_status, presence: true, on: :create
  # The old status row, kept only for deleting a booking: the row's foreign key must be cleared before
  # the booking goes, and its `dependent: :destroy` is what refuses a plain destroy. Nothing writes the
  # row any more, so a booking made since has none; the state of a booking is booking_status_id.
  has_one :sub_space_booking_status,
          dependent: :destroy
  validates :name, presence: true
  validates :description, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time
  validate :times_not_in_past

  # the Google Calendar sync mirrors events that already exist in Google,
  # past ones included (a full sync lists every event). Only that mirror sets
  # this; a booking made in the app may never start in the past.
  attr_accessor :allow_past_start

  # the instant "now" means for this record's past-date check. The
  # booking controller sets it once per request, so a whole recurring series is
  # judged against one clock read; otherwise it is read at validation.
  attr_writer :reference_time

  def reference_time
    @reference_time || Time.current
  end

  # the one past-date rule, for every role (admins and admin blocks
  # included). A booking may not start before now; the current minute counts
  # as now, since the booking form picks whole minutes.
  def self.start_in_past?(start_time, now = Time.current)
    start_time.present? && start_time < now.beginning_of_minute
  end

  # The full past-start error, for a response that has no record to carry it
  # (a recurring series whose occurrences are all in the past).
  def self.past_start_message
    message = I18n.t(:"activerecord.errors.models.sub_space_booking.attributes.start_time.in_the_past")
    I18n.t(:"errors.format", default: "%{attribute} %{message}",
                             attribute: human_attribute_name(:start_time), message: message)
  end

  # the one overlap rule. Exact half-open intersection of [start, end):
  # back-to-back bookings do not overlap, any positive overlap does. Every
  # conflict check goes through here so the paths cannot diverge.
  scope :overlapping,
        lambda { |start_time, end_time|
          where("(sub_space_bookings.start_time, sub_space_bookings.end_time) OVERLAPS (?, ?)",
                start_time, end_time)
        }

  scope :pending, -> { where(booking_status_id: BookingStatus.pending.id) }
  scope :approved, -> { where(booking_status_id: BookingStatus.approved.id) }
  scope :declined, -> { where(booking_status_id: BookingStatus.declined.id) }

  def pending? = booking_status_id == BookingStatus.pending.id
  def approved? = booking_status_id == BookingStatus.approved.id
  def declined? = booking_status_id == BookingStatus.declined.id

  # Saves a new booking with its first status.
  def save_with_status!(status)
    self.booking_status_id = status.id
    save!
  end

  # Changes the status of a saved booking without running validations (a booking that no longer passes
  # some rule can still be approved or declined). Like the two methods below, it sets updated_at, which
  # is how bookings:reconcile_statuses tells a status the app changed from one an old status row holds.
  def change_status!(status)
    update_columns(booking_status_id: status.id, updated_at: Time.current)
  end

  # Approves the booking if it is still pending and says whether this call did it, so only one of two
  # simultaneous approvals goes on to mail the owner. It writes only the status and approval columns
  # (no validations), so a past pending booking can still be approved.
  def approve_if_pending!(by:)
    claimed = self.class.pending.where(id: id).update_all(
      booking_status_id: BookingStatus.approved.id, approved_at: Time.current, approved_by_id: by.id,
      updated_at: Time.current
    )
    return false if claimed.zero?

    reload
    true
  end

  # Declines the booking if it is still pending and says whether this call did it, so only one of two
  # simultaneous declines goes on to mail the owner. It also clears any earlier approval stamp, and
  # writes without validations like approve_if_pending!.
  def decline_if_pending!
    claimed = self.class.pending.where(id: id).update_all(
      booking_status_id: BookingStatus.declined.id, approved_at: nil, approved_by_id: nil, updated_at: Time.current
    )
    return false if claimed.zero?

    reload
    true
  end

  # Gives every booking of the list the status, each through change_status!.
  def self.change_status_of!(bookings, status)
    transaction { bookings.each { |booking| booking.change_status!(status) } }
  end

  # Checks everything except the status, for a new booking whose status is chosen after the checks.
  def valid_without_status?
    valid?(:without_status)
  end

  # Destroys the booking together with its status, the one way a booking is
  # removed. The booking and its status row reference each other, so both links
  # are cleared before either row goes; a booking without a status is simply
  # destroyed. All or nothing.
  def destroy_with_status!
    transaction do
      status = sub_space_booking_status
      status&.update_column(:sub_space_booking_id, nil)
      update_column(:sub_space_booking_status_id, nil)
      status&.destroy!
      destroy!
    end
  end

  # FIXME: THIS DOESNT REALLY WORK FOR ICS TO MAKERROOM AND BREAKS THE GCAL INTEGRATION
  # before_save :upsert_google_booking,
  #   if: ->(sub_space_booking) {[10, 11].include?(sub_space_booking.sub_space_id)}
  
  # before_destroy :delete_google_booking

  def upsert_google_booking
    SubSpaceBooking.upsert_booking(self)
  end

  def delete_google_booking
    SubSpaceBooking.delete_booking(self) if google_booking_id.present?
  end

  def self.authorizer = GoogleCalendar::ServiceAccount.authorizer

  COLOR_LEGEND = [
    {
      id: "your_pending_bookings",
      name: "Your Pending Bookings",
      color: "#B5A500"
    },
    {
      id: "your_confirmed_bookings",
      name: "Your Confirmed Bookings",
      color: "#49794b"
    },
    {
      id: "other_pending_bookings",
      name: "Other Pending Bookings",
      color: "#FFA500"
    },
    {
      id: "other_confirmed_bookings",
      name: "Other Confirmed Bookings",
      color: "#497979"
    },
    { id: "blocking_booking", name: "Blocking Bookings", color: "#ABABABFF" }
  ]

  # The past-date rule applies only while the times are being set. It
  # compares at minute precision, like the form: resubmitting "09:00" for a
  # stored 09:00:30 (a Google-mirrored row) is not a move.
  # - A new booking, or an edit that moves the start: the start may not be in
  #   the past.
  # - A booking in progress (start <= now < its stored end) may move only its
  #   end, to an end after now (extending or shortening it).
  # - A booking that has already ended (stored end <= now) may not have its
  #   times changed at all.
  # A booking that has not started may move its end freely. "Now" is the
  # current minute for every comparison. Saves that leave the times alone
  # (status changes, approvals, renames) keep working on bookings that are now
  # past.
  def times_not_in_past
    return if allow_past_start

    now = reference_time.beginning_of_minute
    if new_record?
      errors.add(:start_time, :in_the_past) if self.class.start_in_past?(start_time, now)
    elsif times_changing?
      stored_end = attribute_in_database(:end_time)
      if stored_end.present? && stored_end <= now
        errors.add(:end_time, :booking_ended)
      elsif minute_changed?(:start_time)
        errors.add(:start_time, :in_the_past) if self.class.start_in_past?(start_time, now)
      elsif self.class.start_in_past?(start_time, now) && end_time.present? && end_time <= now
        errors.add(:end_time, :in_the_past)
      end
    end
  end

  # Whether this save moves the booking, at minute precision (the form picks
  # whole minutes, so "09:00" resubmitted for a stored 09:00:30 is no move).
  # The past-date rule and the controller's duration/week limits share it.
  def times_changing?
    minute_changed?(:start_time) || minute_changed?(:end_time)
  end

  def minute_changed?(attribute)
    to_minute = ->(time) { time&.change(sec: 0) }
    to_minute.call(attribute_in_database(attribute)) != to_minute.call(public_send(attribute))
  end

  def end_time_after_start_time
    return unless start_time.present? && end_time.present? && start_time >= end_time

    errors.add(:end_time, :before_start)
  end

  def self.color_legend
    COLOR_LEGEND
  end

  def color(current_user_id)
    status =
      if blocking
        "blocking_booking"
      elsif approved?
        if user_id == current_user_id
          "your_confirmed_bookings"
        else
          "other_confirmed_bookings"
        end
      elsif user_id == current_user_id
        "your_pending_bookings"
        else
          "other_pending_bookings"
      end
    COLOR_LEGEND.find { |c| c[:id] == status }[:color]
  end

  ##
  # Posts a sub space booking into google cal (or updates an existing one)
  def self.upsert_booking(sub_space_booking)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    attendees = []
    attendees << Google::Apis::CalendarV3::EventAttendee.new(
          email: sub_space_booking.user.email)

    title = sub_space_booking.name

    description = sub_space_booking.description.to_s

    gcal_event = 
      Google::Apis::CalendarV3::Event.new(
        summary: title,
        description: description,
        start:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: sub_space_booking.start_time.iso8601,
            time_zone: "America/Toronto"
          ),
        end:
          Google::Apis::CalendarV3::EventDateTime.new(
            date_time: sub_space_booking.end_time.iso8601,
            time_zone: "America/Toronto"
          ),
          attendees: attendees
      )

    calendar_id = GoogleCalendar::EventPublisher::SHARED_CALENDAR
    if sub_space_booking.google_booking_id.present?
      begin # Update an existing booking
        service.update_event(calendar_id, sub_space_booking.google_booking_id, gcal_event)
      rescue Google::Apis::ClientError => e
        HandledError.report(e, source: "sub_space_booking.upsert_booking", step: "update", sub_space_booking_id: sub_space_booking.id)
      end
    else
      begin #Create a new booking
        Rails.logger.debug "CREATE GOOGLE CAL BOOKING"
        response = service.insert_event(calendar_id, gcal_event)
        sub_space_booking.update(google_booking_id: response.id)
      rescue StandardError => e
        HandledError.report(e, source: "sub_space_booking.upsert_booking", step: "create", sub_space_booking_id: sub_space_booking.id)
      end
    end
  end

  ##
  # Deletes a google event if the sub space booking had one in google cal.
  def self.delete_booking(sub_space_booking)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    
    calendar_id = GoogleCalendar::EventPublisher::SHARED_CALENDAR

    begin
      service.delete_event(calendar_id, sub_space_booking.google_booking_id)
    rescue Google::Apis::ClientError => e
      # Expected outcome, not a failure: Google no longer has the event, so nothing is left to delete.
      return if [404, 410].include?(e.status_code)

      HandledError.report(e, source: "sub_space_booking.delete_booking", sub_space_booking_id: sub_space_booking.id)
    end
  end
end
