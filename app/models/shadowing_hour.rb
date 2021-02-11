class ShadowingHour < ApplicationRecord
  belongs_to :user
  belongs_to :space

  def self.create_event(start_time, end_time, user, space)
    scope = 'https://www.googleapis.com/auth/calendar'

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open("#{Rails.root}/config/makerepo-1632742c49cc.json"),
      scope: scope)

    authorizer.fetch_access_token!

    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = authorizer

    event = Google::Apis::CalendarV3::Event.new(
      summary: "#{user.name} Shadowing",
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time,
        time_zone: 'America/Toronto'
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: end_time,
        time_zone: 'America/Toronto'
      )
    )

    calendar_id = space == "makerspace" ? Rails.application.credentials[Rails.env.to_sym][:calendar][:makerspace] : Rails.application.credentials[Rails.env.to_sym][:calendar][:brunsfield]

    response = service.insert_event(calendar_id, event)

    return response
  end

  def self.delete_event(event_id, space)

    scope = 'https://www.googleapis.com/auth/calendar'

    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open("#{Rails.root}/config/makerepo-1632742c49cc.json"),
      scope: scope)

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
