# frozen_string_literal: true

# Shared by the spec/requests/staff_dashboard_* request specs. Opt-in: include
# StaffDashboardSpecHelpers in the describe block.
module StaffDashboardSpecHelpers
  # Parsed JSON body of the last response (Hash/Array for application/json).
  def json
    response.parsed_body
  end
  alias_method :body, :json

  # Exception class name from the dev-style error page (<h1>NoMethodError in ...</h1>).
  def exception_class
    response.body[/<h1>\s*(\S+)\s+in /, 1]
  end

  # An active lab session (signed in an hour ago, out in 2 hours) for the user.
  # `sp` defaults to the including spec's `space`.
  def sign_in_session(user, sp = space)
    create(:lab_session, user: user, space: sp, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
  end
end
