# frozen_string_literal: true

module PageCrawl
  module RequestOptions
  # Extra request options for routes that need more than path params: query
  # params, headers, a response format. Lambdas receive the world.
  TABLE = {
    "/chat_messages" => ->(w) { { params: { job_order_id: w.records[:job_order]&.id } } },
    "/sub_space_booking/get_sub_space_booking" => ->(w) { { params: { id: w.records[:sub_space_booking]&.id } } },
    "/staff/training_sessions/:id/training_report" => ->(_w) { { format: "xlsx" } },
    "/staff_dashboard/present_users_report" => ->(_w) { { format: "xlsx" } },
    "/admin/certifications/open_modal" => lambda { |w|
      { params: { id: w.records[:certification]&.id }, xhr: true, headers: { "Accept" => "text/javascript" } }
    }
  }.freeze

    def self.for(route, world)
      TABLE[route.path_spec]&.call(world) || {}
    end
  end
end
