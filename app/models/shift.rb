class Shift < ApplicationRecord
  has_and_belongs_to_many :users
  belongs_to :space

  validates :start_datetime, presence: true
  validates :end_datetime, presence: true

  before_save :set_or_update_google_event
  before_destroy :delete_google_event

  def return_event_title
    "#{self.reason} for #{self.users.map(&:name).join(", ")}"
  end

  def color(space_id)
    if users.count == 1
      users.first.staff_spaces.find_by(space_id: space_id).color
    else
      color = users.first.staff_spaces.find_by(space_id: space_id).color
      users.each do |user, i|
        unless i == 0
          color = blend_colors(color, user.staff_spaces.find_by(space_id: space_id).color)
        end
      end
      ('#'+color)
    end
  end

  private

  def to_hex(c)
    n = c.to_i.to_s(16)
    n = '0' + n unless n.length > 1 # 2 characters
    n
  end

  def blend_colors(color1, color2)
    colors = 3.times.map do |i| # R, G, B
      (color2[i*2,2].to_i(16) * 0.5) + (color1[i*2,2].to_i(16) * 0.5)
    end

    colors.map { |a| to_hex(a) }.join
  end

  def set_or_update_google_event
    if self.google_event_id.present?
      Shift.update_event(self).id
    else
      self.google_event_id = Shift.create_event(self).id
    end
  end

  def delete_google_event
    if self.google_event_id.present?
      Shift.delete_event(self)
    end
  end

  def self.authorizer
    scope = 'https://www.googleapis.com/auth/calendar'

    @config = {
      private_key: Rails.application.credentials[Rails.env.to_sym][:google][:private_key],
      client_email: Rails.application.credentials[Rails.env.to_sym][:google][:client_email],
      project_id: Rails.application.credentials[Rails.env.to_sym][:google][:project_id],
      private_key_id: Rails.application.credentials[Rails.env.to_sym][:google][:private_key_id],
      type: Rails.application.credentials[Rails.env.to_sym][:google][:type]
    }

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(@config.to_json, 'r'),
      scope: scope)

    authorizer.sub = 'volunteer@makerepo.com'

    authorizer.fetch_access_token!

    return authorizer
  end

  def self.create_event(shift)

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    attendees = []
    unless Rails.env.test?
      shift.users.each do |user|
        attendees << Google::Apis::CalendarV3::EventAttendee.new(email: user.email)
      end
    end

    event = Google::Apis::CalendarV3::Event.new(
      summary: shift.return_event_title,
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: shift.start_datetime.to_datetime.rfc3339,
        time_zone: 'America/Toronto'
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: shift.end_datetime.to_datetime.rfc3339,
        time_zone: 'America/Toronto'
      ),
      attendees: attendees
    )

    calendar_id = return_space_calendar(shift.space)

    begin
      response = service.insert_event(calendar_id, event, send_notifications: true)
    rescue Google::Apis::ClientError => error
      if error.to_s.include?("Resource has been deleted")
        return response
      else
        return "error"
      end
    rescue Exception
      return "error"
    end

    return response
  end

  def self.update_event(shift)

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    calendar_id = return_space_calendar(shift.space)

    event = service.get_event(calendar_id, shift.google_event_id)
    event.start = Google::Apis::CalendarV3::EventDateTime.new(
      date_time: (shift.start_datetime -= shift.start_datetime.utc_offset).to_datetime.rfc3339,
      time_zone: 'America/Toronto'
    )

    event.end = Google::Apis::CalendarV3::EventDateTime.new(
      date_time: (shift.end_datetime -= shift.end_datetime.utc_offset).to_datetime.rfc3339,
      time_zone: 'America/Toronto'
    )

    begin
      response = service.update_event(calendar_id, shift.google_event_id, event)
    rescue Google::Apis::ClientError => error
      if error.to_s.include?("Resource has been deleted")
        return response
      else
        return "error"
      end
    rescue Exception
      return "error"
    end

    return response
  end

  def self.delete_event(shift)

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    calendar_id = return_space_calendar(shift.space)

    begin
      response = service.delete_event(calendar_id, shift.google_event_id)
    rescue Google::Apis::ClientError => error
      if error.to_s.include?("Resource has been deleted")
        return response
      else
        return "error"
      end
    rescue Exception
      return "error"
    end

    return response
  end

  def self.return_space_calendar(space)
    if Rails.env.test?
      "c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com" # Test Calendar
    elsif space.name == "MTC"
      "c_f6jqt6dcoj7iovfa88a52nh9c4@group.calendar.google.com" # MTC
    else
      "c_g1bk6ctpenjeko2dourrr0h6pc@group.calendar.google.com" # Makerspace
    end
  end
end
