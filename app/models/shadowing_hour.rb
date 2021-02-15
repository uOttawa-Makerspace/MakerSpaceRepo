class ShadowingHour < ApplicationRecord
  belongs_to :user
  belongs_to :space

  def self.create_event(start_time, end_time, user, space)
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

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer
    attendees = !Rails.env.test? ? [Google::Apis::CalendarV3::EventAttendee.new(email: user.email)] : []

    event = Google::Apis::CalendarV3::Event.new(
      summary: "#{user.name} Shadowing",
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time,
        time_zone: 'America/Toronto'
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: end_time,
        time_zone: 'America/Toronto'
      ),
      attendees: attendees
    )

    calendar_id = space == "makerspace" ? Rails.application.credentials[Rails.env.to_sym][:calendar][:makerspace] : Rails.application.credentials[Rails.env.to_sym][:calendar][:brunsfield]

    response = service.insert_event(calendar_id, event, send_notifications: true)

    return response
  end

  def self.delete_event(event_id, space)

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

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    calendar_id = space == "Makerspace" ? Rails.application.credentials[Rails.env.to_sym][:calendar][:makerspace] : Rails.application.credentials[Rails.env.to_sym][:calendar][:brunsfield]

    begin
        response = service.delete_event(calendar_id, event_id)
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
end
