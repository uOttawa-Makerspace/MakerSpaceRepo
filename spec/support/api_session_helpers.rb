# frozen_string_literal: true

# Request specs: sign a user in to /api/v1 and return the token pair
# ("access_token", "refresh_token", ...). `post`/`response` are the caller's.
module ApiSessionHelpers
  def api_token_pair(user, password)
    post "/api/v1/session", params: { login: user.username, password: password }.to_json,
                            headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end
end

RSpec.configure { |config| config.include ApiSessionHelpers, type: :request }
