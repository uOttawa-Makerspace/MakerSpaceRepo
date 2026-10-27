# frozen_string_literal: true

require "rails_helper"

# ApplicationHelper#sign_in / #sign_out / #current_user memoization inside one
# request, driven through a plain host object (no HTTP) so the order of calls
# the controllers make (set_last_seen_at memoizes the user BEFORE the login
# action signs someone else in) is explicit.
RSpec.describe ApplicationHelper do
  let(:host_class) do
    Class.new do
      include ApplicationHelper

      attr_reader :session

      def initialize
        @session = ActiveSupport::HashWithIndifferentAccess.new
      end

      def reset_session
        @session.clear
      end

      attr_writer :headers

      def request
        Struct.new(:headers).new(@headers || {})
      end
    end
  end
  let(:host) { host_class.new }
  let(:password) { "asa32A353#" }
  let!(:first) { create(:user, :regular_user) }
  let!(:second) { create(:user, :regular_user) }

  it "current_user and signed_in? reflect a user signed in after another was memoized in the same request" do
    # FIXED: sign_in clears the memoized session user / current user
    host.session[:user_id] = first.id
    expect(host.signed_in?).to be(true)
    expect(host.current_user).to eq(first)

    expect(host.sign_in(second.username, password)).to eq(second)

    expect(host.signed_in?).to be(true)
    expect(host.current_user).to eq(second)
    expect(host.session[:user_id]).to eq(second.id)
  end

  it "a failed sign_in leaves the memoized user alone" do
    host.session[:user_id] = first.id
    expect(host.current_user).to eq(first)
    expect(host.sign_in(second.username, "wrong")).to be_nil
    expect(host.current_user).to eq(first)
  end

  it "sign_out ends the memoized session" do
    host.session[:user_id] = first.id
    expect(host.current_user).to eq(first)
    host.sign_out
    expect(host.signed_in?).to be(false)
    expect(host.current_user.id).to be_nil
  end

  it "sign_in and sign_out both forget the memoized Bearer user (one reset_auth_memo)" do
    host.headers = { "Authorization" => "Bearer #{first.token}" }
    expect(host.jwt_user).to eq(first)

    host.headers = { "Authorization" => "Bearer #{second.token}" }
    expect(host.jwt_user).to eq(first) # memoized for the rest of the request
    host.sign_out
    expect(host.jwt_user).to eq(second)

    host.headers = { "Authorization" => "Bearer #{first.token}" }
    host.sign_in(second.username, password)
    expect(host.jwt_user).to eq(first)
    expect(host.current_user).to eq(second) # the session user wins over Bearer, as before
  end
end
