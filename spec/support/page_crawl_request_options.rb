# frozen_string_literal: true

module PageCrawl
  module RequestOptions
  # Extra request options for routes that need more than path params: query
  # params, headers, a response format. Lambdas receive the world.
  TABLE = {
    "/job_orders/:job_order_id/task/:id/edit" => ->(_w) { { params: { step: 1 } } },
    "/staff_dashboard/search" => ->(w) { { params: { username: w.records[:target_username] } } },
    "/staff_dashboard/user_profile" => ->(w) { { params: { username: w.records[:target_username] } } },
    "/chat_messages" => ->(w) { { params: { job_order_id: w.records[:job_order]&.id } } },
    "/sub_space_booking/get_sub_space_booking" => ->(w) { { params: { id: w.records[:sub_space_booking]&.id } } },
    "/staff/training_sessions/:id/training_report" => ->(_w) { { format: "xlsx" } },
    "/staff_dashboard/present_users_report" => ->(_w) { { format: "xlsx" } },
    "/admin/certifications/open_modal" => lambda { |w|
      { params: { id: w.records[:certification]&.id }, xhr: true, headers: { "Accept" => "text/javascript" } }
    },
    # The calendar feeds answer for the range the calendar shows, as FullCalendar sends it (Toronto wall time).
    "/staff/unavailabilities/json" => ->(_w) { { params: PageCrawl::RequestOptions.calendar_week } },
    "/admin/calendar/unavailabilities_json/:id" => ->(_w) { { params: PageCrawl::RequestOptions.calendar_week } },
    # The event dialog's staff ranking: the instants of the planned times and the repeat rule as stored.
    "/admin/calendar/staff_conflicts" => lambda { |w|
      start = Time.current.in_time_zone(RecurrenceRule::ZONE).beginning_of_week.change(hour: 10)
      { params: { space_id: w.records[:space]&.id, start: start.utc.iso8601, end: (start + 1.hour).utc.iso8601,
                  recurrence_rule: "DTSTART;TZID=America/Toronto:#{start.strftime('%Y%m%dT%H%M%S')}\nRRULE:FREQ=WEEKLY;BYDAY=MO" } }
    }
  }.freeze

    # The current week as the calendar asks for it.
    def self.calendar_week
      from = Time.current.in_time_zone(RecurrenceRule::ZONE).beginning_of_week(:sunday).to_date
      { start: "#{from}T00:00:00", end: "#{from + 7}T00:00:00" }
    end

    def self.for(route, world)
      TABLE[route.path_spec]&.call(world) || {}
    end
  end
end
