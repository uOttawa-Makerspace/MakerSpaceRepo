# frozen_string_literal: true

# Characterization helpers for the Spaces & scheduling subsystem (chunk 14).
#
# Authentication is the app's own session store, so request specs sign in
# through the real login action (same as the bookings role-matrix spec).
# `current_user` never returns nil (guests get User.new), so the "guest" role
# is simply "no session".
module SpacesSpecHelpers
  ROLE_TRAITS = { regular: :regular_user, staff: :staff, admin: :admin }.freeze

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  # Signs in a user of the given role (nobody for :guest) and returns it.
  def sign_in_as(role, **attrs)
    return nil if role == :guest

    user = create(:user, ROLE_TRAITS.fetch(role), **attrs)
    log_in!(user)
    user
  end

  # BookingStatus::* constants are resolved once at boot against an empty test
  # DB, so point them at real rows (same pattern as the bookings specs).
  def seed_booking_statuses!
    @pending_status = create(:booking_status, :pending)
    @approved_status = create(:booking_status, :approved)
    @declined_status = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending_status)
    stub_const("BookingStatus::APPROVED", @approved_status)
    stub_const("BookingStatus::DECLINED", @declined_status)
  end

  # Builds a minimal iCalendar document. Each event is a hash with :uid,
  # :summary, :start, :end (Time/DateTime, written as UTC) and optional
  # :location, :description, :rrule, :exdate.
  def ics_document(*events)
    fmt = ->(t) { t.utc.strftime("%Y%m%dT%H%M%SZ") }
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//spec//EN"]
    events.each do |e|
      lines << "BEGIN:VEVENT"
      lines << "UID:#{e.fetch(:uid)}"
      lines << "DTSTAMP:#{fmt.call(Time.now)}"
      lines << "DTSTART:#{fmt.call(e.fetch(:start))}"
      lines << "DTEND:#{fmt.call(e.fetch(:end))}"
      lines << "SUMMARY:#{e[:summary] || 'Event'}"
      lines << "DESCRIPTION:#{e[:description]}" if e[:description]
      lines << "LOCATION:#{e[:location]}" if e[:location]
      lines << "RRULE:#{e[:rrule]}" if e[:rrule]
      lines << "EXDATE:#{fmt.call(e[:exdate])}" if e[:exdate]
      lines << "END:VEVENT"
    end
    lines << "END:VCALENDAR"
    lines.join("\r\n") + "\r\n"
  end

  # Stubs the HTTP boundary (HTTParty.get -> Net::HTTP) for an ICS feed.
  def stub_ics(url, body: nil, status: 200)
    stub_request(:get, url).to_return(status: status, body: body.to_s)
  end

  # Runs every call as `role` and expects a bounce to `target` ("/" for
  # AdminAreaController) with an unchanged `state` lambda value.
  def expect_bounced(role, calls, state:, to: "/", flash_alert: nil)
    sign_in_as(role)
    calls.each do |name, call|
      before_state = state.call
      instance_exec(&call)
      expect(response).to redirect_to(to), "#{name} as #{role}: #{response.status}"
      expect(flash[:alert]).to eq(flash_alert), name.to_s
      expect(state.call).to eq(before_state), name.to_s
    end
  end
end
