# frozen_string_literal: true

module GoogleCalendar
  # The service account every Google Calendar call signs in as: the key from the credentials, the calendar
  # scope, acting as the volunteer address. Each call fetches a fresh access token.
  module ServiceAccount
    KEY_FIELDS = %i[private_key client_email project_id private_key_id type].freeze

    def self.authorizer
      key = Rails.application.credentials[Rails.env.to_sym][:google].slice(*KEY_FIELDS)
      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(key.to_json, "r"),
        scope: "https://www.googleapis.com/auth/calendar",
        default_connection: GoogleApiTimeouts.token_connection
      )
      authorizer.sub = "volunteer@makerepo.com"
      authorizer.fetch_access_token!
      authorizer
    end
  end
end
