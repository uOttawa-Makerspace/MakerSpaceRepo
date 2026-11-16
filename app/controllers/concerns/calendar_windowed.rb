# Feeds that take a calendar range (CalendarWindow) answer one they cannot read with 400 and the reason.
module CalendarWindowed
  extend ActiveSupport::Concern

  included do
    rescue_from CalendarWindow::Invalid, with: ->(error) { render json: { error: error.message }, status: :bad_request }
  end
end
