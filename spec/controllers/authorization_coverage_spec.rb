# frozen_string_literal: true

require "rails_helper"

# Route sweep for the authorization guard. For every routed action of a controller that turned the
# guard on (`require_authorization`), the real before_action chain runs as a user who passes the
# gates (an admin; staff and volunteer gates admit admins too) with the action body replaced by a
# no-op, and the spec asserts the request ended with a recorded check or a declared opt-out.
#
# This is a controller-instance sweep, not a request sweep: a request needs valid ids and params
# for ~370 routes and would exercise every action body (mail, HTTP, writes) to prove something the
# filter chain alone shows. The action bodies are never run here; their behaviour is pinned by
# the existing request specs.
RSpec.describe "Authorization guard coverage", type: :controller do
  Route = Struct.new(:klass, :controller, :action, :parts)

  def self.guarded_routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next unless controller && action

      klass = "#{controller.camelize}Controller".safe_constantize
      next unless klass.respond_to?(:authorization_required) && klass.authorization_required

      Route.new(klass, controller, action, route.required_parts)
    end.uniq { |r| [r.controller, r.action] }
  end

  let(:user) { create(:user, :admin) }

  def run_filters(route)
    controller = route.klass.new
    request = ActionController::TestRequest.create(route.klass)
    request.path_parameters = route.parts.to_h { |part| [part, "1"] }.merge(controller: route.controller, action: route.action)
    controller.set_request!(request)
    controller.set_response!(route.klass.make_response!(request))
    sign_in_stubs(controller)
    stub_action_body(controller, route.action)
    begin
      controller.process(route.action)
    rescue StandardError
      nil # a filter after the gate may fail on the placeholder ids; only the gate matters here
    end
    controller
  end

  def sign_in_stubs(controller)
    controller.define_singleton_method(:current_user) { user_for_sweep }
    controller.define_singleton_method(:session_user) { user_for_sweep }
    controller.instance_variable_set(:@sweep_user, user)
    controller.define_singleton_method(:user_for_sweep) { @sweep_user }
  end

  def stub_action_body(controller, action)
    return unless controller.class.action_methods.include?(action)

    controller.define_singleton_method(action) { head :ok }
  end

  routes = guarded_routes

  it "covers the admin, staff, development program, volunteer and API areas" do
    controllers = routes.map(&:controller)
    expect(routes.size).to be > 300
    expect(controllers).to include("admin/users", "printers", "carts", "volunteers", "api/v1/users")
  end

  it "only opts out actions that are routed" do
    routes.map(&:klass).uniq.each do |klass|
      routed = routes.select { |r| r.klass == klass }.map(&:action)
      expect(klass.authorization_skips.keys - routed - (klass.superclass.try(:authorization_skips) || {}).keys).to be_empty, "#{klass} skips an action that is not routed"
    end
  end

  routes.each do |route|
    it "#{route.controller}##{route.action} records a check or declares why not" do
      controller = run_filters(route)

      expect(controller.send(:authorization_checked?)).to be(true),
        "#{route.controller}##{route.action} passed its gates without authorized!"
    end
  end
end
