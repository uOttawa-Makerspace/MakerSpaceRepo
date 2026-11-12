# frozen_string_literal: true

require "rails_helper"

# The public data the Design Day app reads. Reading never creates the design day row; saving does.
RSpec.describe "GET /admin/design_day/data", type: :request do
  after { DesignDay.unscoped.find_each(&:destroy) }

  it "answers the blank default without creating a row when none exists" do
    DesignDay.unscoped.delete_all
    expect { get "/admin/design_day/data" }.not_to change(DesignDay.unscoped, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "id" => nil, "day" => Time.zone.today.to_s, "is_live" => false, "sheet_key" => "", "show_floorplans" => true,
      "semester" => DesignDay.new(day: Time.zone.today).semester.to_s, "year" => Time.zone.today.year,
      "floorplan_urls" => nil, "floorplan_titles" => nil, "design_day_schedules" => []
    )
  end

  it "answers the saved row unchanged" do
    row = DesignDay.create!(day: Date.new(2026, 3, 14), sheet_key: "KEY123", is_live: true, show_floorplans: false)
    get "/admin/design_day/data"
    expect(response.parsed_body).to eq(
      "id" => row.id, "day" => "2026-03-14", "is_live" => true, "sheet_key" => "KEY123", "show_floorplans" => false,
      "semester" => "winter", "year" => 2026, "floorplan_urls" => nil, "floorplan_titles" => nil,
      "design_day_schedules" => []
    )
  end

  it "still creates the row when an admin opens the form" do
    DesignDay.unscoped.delete_all
    sign_in_as(:admin)
    expect { get "/admin/design_day" }.to change(DesignDay.unscoped, :count).by(1)
  end
end
