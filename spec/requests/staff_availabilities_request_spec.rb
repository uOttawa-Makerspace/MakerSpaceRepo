# frozen_string_literal: true

require "rails_helper"

# /staff_availabilities routes (resources + get_availabilities) point at a
# StaffAvailabilitiesController that does not exist. StaffAvailability and
# StaffAvailabilityException are only reachable through TimePeriod
# (dependent: :destroy, see admin_time_periods_request_spec.rb) and the model
# specs.

RSpec.describe "StaffAvailabilities", type: :request do
  include SpacesSpecHelpers

  # WART(D-SP19): routes for a missing StaffAvailabilitiesController: every request raises (uninitialized constant) and answers 500, signed in or not.
  it "has no controller behind any /staff_availabilities route" do
    [:guest, :admin].each do |role|
      sign_in_as(role)
      get staff_availabilities_path
      expect(response).to have_http_status(:internal_server_error), role.to_s
      get get_availabilities_staff_availabilities_path
      expect(response).to have_http_status(:internal_server_error), role.to_s
      post staff_availabilities_path, params: { staff_availability: { day: 1 } }
      expect(response).to have_http_status(:internal_server_error), role.to_s
      expect(StaffAvailability.count).to eq(0)
    end
  end
end
