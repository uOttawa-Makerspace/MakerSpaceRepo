# frozen_string_literal: true

require "rails_helper"

# Routes that were generated without an action behind them (or were a second
# spelling of another route) are gone. Each example checks that the path no
# longer reaches the named controller, and that the neighbouring routes that
# are still used keep working.
RSpec.describe "Removed routes", type: :routing do
  def reaches?(verb, path, controller)
    found = Rails.application.routes.recognize_path(path, method: verb)
    "#{found[:controller]}##{found[:action]}" == controller || found[:controller] == controller
  rescue ActionController::RoutingError
    false
  end

  [
    [:get, "/coupon_codes/new", "coupon_codes"],
    [:get, "/custom_webhooks", "custom_webhooks"],
    [:post, "/custom_webhooks", "custom_webhooks"],
    [:delete, "/custom_webhooks/1", "custom_webhooks"],
    [:get, "/lockers/new", "lockers#new"],
    [:get, "/lockers/1/edit", "lockers#edit"],
    [:get, "/admin/trainings/1", "admin/trainings"],
    [:get, "/admin/skills/1", "admin/skills"],
    [:get, "/admin/drop_off_locations/1", "admin/drop_off_locations"],
    [:get, "/admin/certifications/search_demotions", "admin/certifications#search_demotions"],
    [:post, "/admin/calendar", "admin/calendar"],
    [:get, "/admin/calendar/1", "admin/calendar"],
    [:get, "/staff/training_sessions/1/edit", "staff/training_sessions"],
    [:get, "/staff/my_calendar/1", "staff/my_calendar"],
    [:get, "/staff/unavailabilities/new", "staff/unavailabilities"],
    [:get, "/staff/unavailabilities/1", "staff/unavailabilities"],
    [:post, "/exams", "exams"],
    [:get, "/staff_spaces", "staff_spaces"],
    [:delete, "/staff_spaces/1", "staff_spaces"],
    [:get, "/walk_in_safety_sheets/1/edit", "walk_in_safety_sheets"],
    [:get, "/admin/job_types", "admin/job_types"],
    [:get, "/admin/job_services", "admin/job_services"],
    [:get, "/admin/job_options", "admin/job_options"],
    [:get, "/admin/job_service_groups", "admin/job_service_groups"],
    [:delete, "/project_proposals/destroy/1", "project_proposals"],
    [:patch, "/admin/training_sessions/1/update", "admin/training_sessions"]
  ].each do |verb, path, controller|
    it "no longer routes #{verb.to_s.upcase} #{path} to #{controller}" do
      expect(reaches?(verb, path, controller)).to be(false)
    end
  end

  it "routes GET / to the home page only" do
    expect(get: "/").to route_to("static_pages#home")
  end

  describe "routes that stay" do
    it "keeps the Shopify webhooks" do
      expect(post: "/custom_webhooks/orders_paid").to route_to("custom_webhooks#orders_paid")
      expect(post: "/custom_webhooks/orders_fulfilled").to route_to("custom_webhooks#orders_fulfilled")
    end

    it "keeps the staff space bulk upload" do
      expect(post: "/staff_spaces/bulk_add_users").to route_to("staff_spaces#bulk_add_users")
    end

    it "keeps the admin job settings forms" do
      expect(get: "/admin/job_types/new").to route_to("admin/job_types#new")
      expect(post: "/admin/job_types").to route_to("admin/job_types#create")
      expect(patch: "/admin/job_options/1").to route_to("admin/job_options#update", id: "1")
      expect(delete: "/admin/job_services/1").to route_to("admin/job_services#destroy", id: "1")
      expect(get: "/admin/job_service_groups/1/edit").to route_to("admin/job_service_groups#edit", id: "1")
    end

    it "keeps the update and delete routes whose GET show was removed" do
      expect(patch: "/admin/trainings/1").to route_to("admin/trainings#update", id: "1")
      expect(delete: "/admin/drop_off_locations/1").to route_to("admin/drop_off_locations#destroy", id: "1")
      expect(patch: "/staff/unavailabilities/1").to route_to("staff/unavailabilities#update", id: "1")
      expect(patch: "/admin/training_sessions/1").to route_to("admin/training_sessions#update", id: "1")
      expect(delete: "/project_proposals/1").to route_to("project_proposals#destroy", id: "1")
    end

    it "keeps the calendar pages and the path helpers in use" do
      expect(get: "/admin/calendar").to route_to("admin/calendar#index")
      expect(get: "/staff/my_calendar").to route_to("staff/my_calendar#index")
      expect(admin_calendar_index_path).to eq("/admin/calendar")
      expect(staff_unavailability_path(1)).to eq("/staff/unavailabilities/1")
      expect(admin_job_types_path).to eq("/admin/job_types")
    end

    it "keeps one staff training sessions index and the Track Hours form" do
      expect(get: "/staff/training_sessions").to route_to("staff/training_sessions#index")
      expect(get: "/volunteer_hours/new").to route_to("volunteer_hours#new")
    end
  end
end
