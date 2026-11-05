# frozen_string_literal: true

module Api
  module V1
    # Public Design Day configuration (replaces GET /admin/design_day/data for the Design Day
    # app). No auth, no cookies. CORS: the Design Day origins only (config/initializers/cors.rb).
    # Contract: doc/api/v1/design_day.md.
    class DesignDaysController < BaseController
      # Sets url options so the disk service can build public floorplan urls.
      include ActiveStorage::SetCurrent

      def show
        render json: DesignDaySerializer.call(design_day)
      end

      private

      # Legacy DesignDay.instance creates a row when none exists; a public GET must not write.
      def design_day
        DesignDay.includes(:design_day_schedules, floorplans_attachments: :blob).first ||
          DesignDay.new(day: Time.zone.today, sheet_key: "", is_live: false, show_floorplans: false)
      end
    end
  end
end
