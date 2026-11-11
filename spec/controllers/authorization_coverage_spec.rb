# frozen_string_literal: true

require "rails_helper"

# Route sweep for the authorization guard. For every routed action of a controller that turned the
# guard on (`require_authorization`), the real before_action chain runs as a user who passes the
# gates (an admin; staff and volunteer gates admit admins too) with the action body replaced by a
# no-op. The spec asserts the request ended with a recorded check, or that the action is opted out
# and no gate records a check for it (an opt-out that a gate now covers is stale).
#
# This is a controller-instance sweep, not a request sweep: a request needs valid ids and params
# for ~380 routes and would exercise every action body (mail, HTTP, writes) to prove something the
# filter chain alone shows. The action bodies are never run here; their behaviour is pinned by
# the existing request specs.
RSpec.describe "Authorization guard coverage", type: :controller do
  sweep_route = Struct.new(:klass, :controller, :action, :parts)

  routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    next unless controller && action

    klass = "#{controller.camelize}Controller".safe_constantize
    next unless klass.respond_to?(:authorization_required) && klass.authorization_required

    sweep_route.new(klass, controller, action, route.required_parts)
  end.uniq { |r| [r.controller, r.action] }

  let(:user) { create(:user, :admin) }

  def run_filters(route)
    controller = route.klass.new
    request = ActionController::TestRequest.create(route.klass)
    request.path_parameters = route.parts.to_h { |part| [part, "1"] }.merge(controller: route.controller, action: route.action)
    controller.set_request!(request)
    controller.set_response!(route.klass.make_response!(request))
    sign_in_stubs(controller)
    stub_action_body(controller, route.action)
    controller.process(route.action)
    controller
  end

  def sign_in_stubs(controller)
    signed_in_user = user
    controller.define_singleton_method(:current_user) { signed_in_user }
    controller.define_singleton_method(:session_user) { signed_in_user }
  end

  def stub_action_body(controller, action)
    return unless controller.class.action_methods.include?(action)

    controller.define_singleton_method(action) { head :ok }
  end

  it "covers the admin, staff, development program, volunteer and API areas" do
    controllers = routes.map(&:controller)
    expect(routes.size).to be > 300
    expect(controllers).to include("admin/users", "printers", "carts", "volunteers", "api/v1/users")
  end

  it "only opts out actions that are routed" do
    routes.map(&:klass).uniq.each do |klass|
      routed = routes.select { |r| r.klass == klass }.map(&:action)
      expect(klass.authorization_skips.keys - routed).to be_empty, "#{klass} skips an action that is not routed"
    end
  end

  it "counts the opt-outs that stand in for a check the rollout has yet to add" do
    pending_skips = routes.map(&:klass).uniq.flat_map do |klass|
      klass.authorization_skips.select { |_, reason| reason.start_with?(Authorization::ROLLOUT_PENDING) }.keys.map { |a| "#{klass}##{a}" }
    end
    puts "authorization rollout pending: #{pending_skips.size} opt-outs (#{pending_skips.join(', ')})"
    expect(pending_skips).not_to be_empty
  end

  routes.each do |route|
    it "#{route.controller}##{route.action} records a check or declares why not" do
      controller = run_filters(route)
      skipped = route.klass.authorization_skips.key?(route.action)

      if skipped
        expect(controller.send(:authorization_recorded?)).to be(false),
          "#{route.controller}##{route.action} is opted out but a gate records a check: remove the opt-out"
      else
        expect(controller.send(:authorization_recorded?)).to be(true),
          "#{route.controller}##{route.action} passed its gates without record_authorization!"
      end
    end
  end
end
