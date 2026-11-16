# frozen_string_literal: true

require "rails_helper"

# The sign-in pop-up shows who signed in; its animated timer bar only counts down to the
# pop-up closing, so it is hidden from assistive technology instead of reporting a fixed value.
RSpec.describe "Staff dashboard sign-in modal", type: :request do
  include StaffDashboardSpecHelpers

  let!(:space) { create(:space) }
  let!(:staff) { sign_in_as(:staff, space: space) }

  it "marks the timer bar decorative and gives it no progress value" do
    get staff_dashboard_index_path

    bar = Nokogiri::HTML(response.body).at_css("#signinModal #outer-progress-bar")
    expect(bar["aria-hidden"]).to eq("true")
    expect(bar.attributes.keys).not_to include("role", "aria-valuenow", "aria-valuemin", "aria-valuemax", "aria-label")
  end
end
