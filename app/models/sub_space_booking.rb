class SubSpaceBooking < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :sub_space
  belongs_to :recurring_booking, optional: true
  has_one :sub_space_booking_status,
          dependent: :destroy
  validates :name, presence: true
  validates :description, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time

  before_save :upsert_google_booking,
    if: ->(sub_space_booking) {[10, 11].include?(sub_space_booking.sub_space_id)}
  
  before_destroy :delete_google_booking

  def upsert_google_booking
    SubSpaceBooking.upsert_booking(self)
  end

  def delete_google_booking
    SubSpaceBooking.delete_booking(self) if google_booking_id.present?
  end

  def self.authorizer # rubocop:disable Metrics/AbcSize
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
    authorizer
  end

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

  def end_time_after_start_time
    return unless start_time.present? && end_time.present? && start_time >= end_time
      errors.add(:expiration_date, "Start Time needs to be before end time")
    
  end

  def self.color_legend
    COLOR_LEGEND
  end

  def color(current_user_id)
    status =
      if blocking
        "blocking_booking"
      elsif SubSpaceBookingStatus.find(
            sub_space_booking_status_id
          ).booking_status_id == BookingStatus::APPROVED.id
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

    calendar_id = return_sub_space_calendar(sub_space_booking.sub_space)
    if sub_space_booking.google_booking_id.present?
      begin # Update an existing booking
        service.update_event(calendar_id, sub_space_booking.google_booking_id, gcal_event)
      rescue Google::Apis::ClientError => e
        Rails.logger.error "Failed to update Google sub space booking #{sub_space_booking.id}: #{e.message}"
      end
    else
      begin #Create a new booking
        Rails.logger.debug "CREATE GOOGLE CAL BOOKING"
        response = service.insert_event(calendar_id, gcal_event)
        sub_space_booking.update(google_booking_id: response.id)
      rescue StandardError => e
        Rails.logger.error "Failed to create booking #{sub_space_booking.id}: #{e.message}"
      end
    end
  end

  def self.delete_booking(sub_space_booking)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    
    calendar_id = return_sub_space_calendar(sub_space_booking.sub_space)

    begin
      response = service.delete_event(calendar_id, sub_space_booking.google_booking_id)
    rescue Google::Apis::ClientError => e
      Rails.logger.error "Failed to delete Google event #{sub_space_booking.id}: #{e.message}"
    end
  end

  def self.return_sub_space_calendar(sub_space)
    if sub_space.name == "STM 124"
      "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com"
    elsif sub_space.name == "STM 126"
      "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com"
    else
      "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" # my personal test calendar
    end
  end
end
