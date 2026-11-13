# frozen_string_literal: true

# Rack middleware in front of the app server that system specs browse. An
# example may freeze the server clock (travel_to) while the browser keeps the
# real one. The server dates each cookie's expiry on its own clock (the session
# cookie expires a week after the server's now), so a browser whose real date
# is more than a week past the frozen one would drop the session cookie as
# already expired. A browser reads a cookie's expiry relative to the response's
# Date header when there is one, so this sends the server's now as the Date of
# every response that has none (Puma adds none; some actions set it, such as
# those that set cache headers). The server still checks the expiry it stores
# inside the session cookie on its own clock.
class ServerDateHeader
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["date"] ||= Time.now.utc.httpdate
    [status, headers, body]
  end
end
