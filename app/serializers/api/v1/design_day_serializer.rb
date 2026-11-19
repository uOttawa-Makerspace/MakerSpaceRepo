# frozen_string_literal: true

module Api
  module V1
    # Explicit allowlist: no id, is_live or timestamps. Floorplan lists are always arrays.
    module DesignDaySerializer
      module_function

      def call(design_day)
        floorplans = design_day.floorplans.attached? ? design_day.floorplans.to_a : []
        {
          year: design_day.year,
          semester: design_day.semester,
          day: design_day.day,
          sheet_key: design_day.sheet_key,
          show_floorplans: design_day.show_floorplans,
          show_floorplans_day2: design_day.show_floorplans_day2,
          floorplan_urls: floorplans.map(&:url),
          floorplan_titles: floorplans.map { |f| f.metadata[:floorplan_title] },
          floorplan_days: design_day.floorplan_days || []
        }
      end
    end
  end
end
