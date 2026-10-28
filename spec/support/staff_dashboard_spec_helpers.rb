# frozen_string_literal: true

# Shared by the spec/requests/staff_dashboard_* request specs. Opt-in: include
# StaffDashboardSpecHelpers in the describe block.
module StaffDashboardSpecHelpers
  # Parsed JSON body of the last response (string keys). Raises on a non-JSON
  # response (HTML 500, redirect) so a wrong status fails loudly.
  def json
    JSON.parse(response.body)
  end

  def body = json

  # Exception class name from the dev-style error page (<h1>NoMethodError in ...</h1>).
  def exception_class
    response.body[/<h1>\s*(\S+)\s+in /, 1]
  end

  # A lab session signed in an hour ago and signing out `sign_out_in` from now.
  # The space is explicit so a missing one fails clearly.
  def sign_in_session(user, space, sign_out_in: 2.hours)
    create(:lab_session, user: user, space: space, sign_in_time: 1.hour.ago, sign_out_time: sign_out_in.from_now)
  end
end
