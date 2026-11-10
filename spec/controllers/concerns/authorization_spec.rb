# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authorization, type: :controller do
  controller(ApplicationController) do
    require_authorization
    skip_authorization only: :open, reason: "Public test page"

    def checked
      authorized!(:test)
      head :ok
    end

    def unchecked
      head :ok
    end

    def open
      head :ok
    end

    def guarded
      authorize!(record, :editable_by?)
      head :ok unless performed?
    end

    def record
      Class.new do
        def editable_by?(user) = user.respond_to?(:admin?) && user.admin?
      end.new
    end
  end

  before do
    routes.draw do
      get "checked" => "anonymous#checked"
      get "unchecked" => "anonymous#unchecked"
      get "open" => "anonymous#open"
      get "guarded" => "anonymous#guarded"
    end
  end

  it "lets an action through once a check was recorded" do
    get :checked
    expect(response).to have_http_status(:ok)
  end

  it "lets an opted-out action through" do
    get :open
    expect(response).to have_http_status(:ok)
  end

  it "raises in test when no check was recorded" do
    expect { get :unchecked }.to raise_error(Authorization::NotChecked, /anonymous#unchecked/)
  end

  context "in production" do
    before { allow(Rails.env).to receive(:local?).and_return(false) }

    it "reports through Rails.error with the controller and action, and does not block" do
      allow(Rails.error).to receive(:report)
      get :unchecked
      expect(response).to have_http_status(:ok)
      expect(Rails.error).to have_received(:report).with(
        an_instance_of(Authorization::NotChecked), handled: true, severity: :error,
        context: { controller: "anonymous", action: "unchecked" }
      )
    end
  end

  describe "authorize!" do
    it "records the check when the predicate holds" do
      allow(controller).to receive(:current_user).and_return(build_stubbed(:user, :admin))
      get :guarded
      expect(response).to have_http_status(:ok)
    end

    it "sends a page back home when the predicate fails" do
      allow(controller).to receive(:current_user).and_return(build_stubbed(:user, :regular_user))
      get :guarded
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end

    it "answers 403 to a script request when the predicate fails" do
      allow(controller).to receive(:current_user).and_return(build_stubbed(:user, :regular_user))
      get :guarded, format: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe ".skip_authorization" do
    it "needs a reason" do
      expect { Class.new(ApplicationController) { skip_authorization only: :a, reason: " " } }
        .to raise_error(ArgumentError, /reason/)
    end

    it "does not leak to the parent controller" do
      Class.new(ApplicationController) { skip_authorization only: :a, reason: "x" }
      expect(ApplicationController.authorization_skips).to eq({})
    end
  end

  it "turns the guard on once per controller chain" do
    parent = Class.new(ApplicationController) { require_authorization }
    child = Class.new(parent) { require_authorization }
    expect(child._process_action_callbacks.count { |cb| cb.filter == :verify_authorized }).to eq(1)
  end
end
