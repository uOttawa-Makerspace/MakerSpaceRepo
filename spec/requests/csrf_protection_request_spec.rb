# frozen_string_literal: true

require "rails_helper"

# INF-01/IDN-07: ApplicationController used to declare
# `protect_from_forgery with: :null_session, only: proc { ... }`. `only:` takes
# action names, the proc became a string that never matched, and the
# declaration replaced the framework's default one, so verify_authenticity_token
# never ran anywhere (and the cross-origin JavaScript guard was off too).
#
# The contract pinned here:
# - every non-GET HTML/JS/form request needs the session's token (422 without);
# - the only exemption is a legacy JSON request: Content-Type application/json
#   (which a cross-site page cannot send without a CORS preflight) AND asking
#   for JSON. A form posting to a .json path or with ?format=json is checked;
# - external callers (Shopify, Google Calendar push, tap boxes) are exempt in
#   their own controller and authenticate themselves.
RSpec.describe "CSRF protection", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "asa32A353#" }
  let(:user) { create(:user, :regular_user) }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }

  # The token a browser gets: the csrf-token meta tag of a page this session rendered.
  def page_token(path = root_path)
    get path
    Nokogiri::HTML(response.body).at_css("meta[name='csrf-token']")["content"]
  end

  # Signs in through the real login form, token included.
  def log_in!(u = user)
    post login_authentication_path,
         params: { username_email: u.username, password: password, authenticity_token: page_token(login_path) }
    expect(response).to redirect_to(root_path)
  end

  def signed_in?
    get check_signed_in_path
    response.parsed_body["signed_in"] == "true"
  end

  let(:stale_form_message) { "Your session changed; please try again." }

  # A refused HTML form (a stale tab, or a forged form) is sent back with a flash,
  # not a bare 422 page.
  def expect_stale_form_redirect(target)
    expect(response).to redirect_to(target)
    expect(flash[:alert]).to eq(stale_form_message)
  end

  def expect_stale_form_json_refusal
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => stale_form_message)
  end

  it "is on in the test env, as in production" do
    expect(ActionController::Base.allow_forgery_protection).to be(true)
  end

  describe "HTML requests" do
    it "an HTML POST without a token is refused and changes nothing (sign out)" do
      log_in!
      post perform_logout_path, without_csrf_token: true
      expect_stale_form_redirect(root_path)
      expect(signed_in?).to be(true)
    end

    it "an HTML POST with the page's token goes through" do
      log_in!
      post perform_logout_path, params: { authenticity_token: page_token }
      expect(response).to redirect_to(root_path)
      expect(signed_in?).to be(false)
    end

    it "the token can also come in the X-CSRF-Token header (fetch, Turbo)" do
      log_in!
      delete perform_logout_path, headers: { "X-CSRF-Token" => page_token }
      expect(response).to redirect_to(root_path)
      expect(signed_in?).to be(false)
    end

    it "a token from another session is refused" do
      other_token = page_token
      log_in! # sign-in resets the session, so the token above is stale
      post perform_logout_path, params: { authenticity_token: other_token }
      expect_stale_form_redirect(root_path)
      expect(signed_in?).to be(true)
    end

    it "the login form itself needs the token (login CSRF)" do
      post login_authentication_path, params: { username_email: user.username, password: password }, without_csrf_token: true
      expect_stale_form_redirect(login_path)
      expect(signed_in?).to be(false)
    end

    it "an HTML form POST to a .json path without a token is refused" do
      log_in!
      post "/logout.json", params: { foo: "bar" }, without_csrf_token: true # urlencoded, as a form sends it
      expect_stale_form_json_refusal
      expect(signed_in?).to be(true)
    end

    it "an HTML form POST with ?format=json, or a text/plain body to a .json path, is refused" do
      log_in!
      post "/logout?format=json", params: { foo: "bar" }, without_csrf_token: true
      expect_stale_form_json_refusal
      post "/logout.json", params: '{"foo":"bar"}', headers: { "CONTENT_TYPE" => "text/plain" }, without_csrf_token: true
      expect_stale_form_json_refusal
      expect(signed_in?).to be(true)
    end

    it "a JSON body that does not ask for JSON is checked (the exemption needs both)" do
      log_in!
      post perform_logout_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "text/html" },
                                without_csrf_token: true
      expect_stale_form_redirect(root_path)
      expect(signed_in?).to be(true)
    end

    it "a refused form goes back to the page it came from (same host only)" do
      log_in!
      post perform_logout_path, headers: { "Referer" => "http://www.example.com/settings/profile" }, without_csrf_token: true
      expect_stale_form_redirect("http://www.example.com/settings/profile")
      post perform_logout_path, headers: { "Referer" => "https://evil.example/forged.html" }, without_csrf_token: true
      expect_stale_form_redirect(root_path)
    end

    it "a signed-out stale tab is sent to sign in, keeping its page as back_to" do
      post perform_logout_path, headers: { "Referer" => "http://www.example.com/settings/profile" }, without_csrf_token: true
      expect_stale_form_redirect(login_path(back_to: "/settings/profile"))
    end

    it "a stale login form keeps the login page's own back_to (no nested /login?back_to=/login...), so sign-in lands there" do
      get login_path(back_to: "/settings/profile")
      login_page = "http://www.example.com#{login_path(back_to: "/settings/profile")}"
      post login_authentication_path, params: { username_email: user.username, password: password },
                                      headers: { "Referer" => login_page }, without_csrf_token: true
      expect_stale_form_redirect(login_path(back_to: "/settings/profile"))

      follow_redirect!
      form = Nokogiri::HTML(response.body).at_css("form[action='#{login_authentication_path}']")
      fields = form.css("input[type='hidden']").to_h { |input| [input["name"], input["value"]] }
      post login_authentication_path, params: fields.merge("username_email" => user.username, "password" => password)
      expect(response).to redirect_to("http://www.example.com/settings/profile")
    end

    it "an XHR or JS request is answered 422 with the message" do
      log_in!
      post perform_logout_path, headers: { "X-Requested-With" => "XMLHttpRequest" }, without_csrf_token: true
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(stale_form_message)
      post perform_logout_path, headers: { "ACCEPT" => "text/javascript" }, without_csrf_token: true
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(stale_form_message)
      expect(signed_in?).to be(true)
    end

    it "a Turbo form submission (turbo-stream first in Accept) is redirected like a browser form" do
      log_in!
      post perform_logout_path, headers: { "ACCEPT" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" },
                                without_csrf_token: true
      expect_stale_form_redirect(root_path)
    end

    it "a request for another format (XML) gets a 422 with the message, not a redirect to an HTML page" do
      log_in!
      post perform_logout_path, headers: { "ACCEPT" => "application/xml" }, without_csrf_token: true
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(stale_form_message)
    end

    it "logs only the exception class, never the submitted token or params" do
      log_in!
      logged = []
      allow(Rails.logger).to receive(:warn).and_wrap_original { |m, *args, &blk| logged << args.first.to_s; m.call(*args, &blk) }
      post perform_logout_path, params: { authenticity_token: "forged-token-value", secret_field: "s3cr3t" }
      expect(logged).to include("CSRF check failed: ActionController::InvalidAuthenticityToken")
      expect(logged.join).not_to include("forged-token-value", "s3cr3t")
    end

    it "a GET answered with JavaScript is only served to same-origin XHR (cross-origin JS guard)" do
      create(:user, :staff).tap { |staff| log_in!(staff) }
      get badges_path, headers: { "ACCEPT" => "text/javascript" }
      expect(response).to have_http_status(:unprocessable_content)
      get badges_path, headers: { "ACCEPT" => "text/javascript", "X-Requested-With" => "XMLHttpRequest" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "the cached home page" do
    around do |example|
      store, caching = ActionController::Base.cache_store, ActionController::Base.perform_caching
      ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
      ActionController::Base.perform_caching = true
      example.run
    ensure
      ActionController::Base.cache_store = store
      ActionController::Base.perform_caching = caching
    end

    before do
      stub_request(:get, %r{\Ahttps://simpli\.events/}).to_return(status: 500)
      stub_request(:post, %r{\Ahttps://[^/]+\.myshopify\.com/}).to_return(status: 500)
    end

    # The hidden fields of the home page's sign-out button_to (_method, authenticity_token).
    def sign_out_form_fields
      form = Nokogiri::HTML(response.body).css("#home-userinfo form").find { |f| f["action"] == perform_logout_path }
      form.css("input[type='hidden']").to_h { |input| [input["name"], input["value"]] }
    end

    # Ruby seeds #hash per process, so a key built from Array#hash differs in every
    # server worker. The key is a digest of the recent projects' cache versions
    # and of the workshops' JSON instead.
    it "uses a key that is the same in every process (digests, not Ruby #hash values)" do
      repo = create(:repository)
      log_in!
      get root_path
      projects = Repository.public_repos.order(created_at: :desc).limit(15).to_a
      expect(projects).to include(repo)
      projects_digest = ActiveSupport::Digest.hexdigest(projects.map(&:cache_key_with_version).join(","))
      workshops_digest = ActiveSupport::Digest.hexdigest([].to_json)
      keys = ActionController::Base.cache_store.instance_variable_get(:@data).keys.grep(%r{\Aviews/static_pages/home})
      expect(keys.size).to eq(2)
      expect(keys).to all(include("/#{projects_digest}/#{workshops_digest}/"))
    end

    it "is cached per user, not per session: a second session of the same user reuses the entries" do
      log_in!
      get root_path
      entries = ActionController::Base.cache_store.instance_variable_get(:@data).keys
      expect(entries).not_to be_empty
      reset! # another browser: a new session for the same user
      log_in!
      get root_path
      expect(ActionController::Base.cache_store.instance_variable_get(:@data).keys).to match_array(entries)
    end

    it "keeps the token-bearing forms (sign out, announcement dismiss) out of the cached fragments" do
      create(:announcement, public_goal: "all", description: "Hello all")
      log_in!
      get root_path
      cached = ActionController::Base.cache_store.instance_variable_get(:@data).values.map { |e| e.value.to_s }.join
      expect(cached).not_to include("authenticity_token")
    end

    it "does not hand a new session the sign-out form (and its token) cached for the previous one" do
      log_in!
      get root_path # cached for this session
      post perform_logout_path, params: sign_out_form_fields
      expect(signed_in?).to be(false)

      log_in! # same user, new session, new token
      get root_path
      post perform_logout_path, params: sign_out_form_fields
      expect(response).to redirect_to(root_path)
      expect(signed_in?).to be(false)
    end
  end

  describe "legacy JSON requests (React apps with the cookie session)" do
    it "JSON login, as MakerRepoApp sends it, works without a token" do
      post login_authentication_path,
           params: { username_email: user.username, password: password }.to_json, headers: json_headers,
           without_csrf_token: true
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["signed_in"]).to be(true)
      expect(signed_in?).to be(true)
    end

    it "a cookie-authenticated JSON PUT (staff_dashboard/change_space) works without a token" do
      staff = create(:user, :staff)
      space = create(:space)
      post login_authentication_path,
           params: { username_email: staff.username, password: password }.to_json, headers: json_headers,
           without_csrf_token: true
      put "/staff_dashboard/change_space?space_id=#{space.id}", params: "{}", headers: json_headers, without_csrf_token: true
      expect(response).to have_http_status(:ok)
      expect(staff.reload.space_id).to eq(space.id)
    end

    it "with a charset parameter on the Content-Type, still works" do
      post login_authentication_path,
           params: { username_email: user.username, password: password }.to_json,
           headers: json_headers.merge("CONTENT_TYPE" => "application/json; charset=utf-8"), without_csrf_token: true
      expect(response).to have_http_status(:ok)
    end
  end

  describe "external callers (no token, their own authentication)" do
    let(:order_body) { { id: 1, tags: "" }.to_json }

    it "Shopify orders_paid webhook: a signed one is processed" do
      post orders_paid_custom_webhooks_path, params: order_body, headers: shopify_webhook_headers(order_body),
                                             without_csrf_token: true
      expect(response).to have_http_status(:ok)
    end

    it "Shopify orders_paid webhook: an unsigned one is still refused by the HMAC check" do
      post orders_paid_custom_webhooks_path, params: order_body, headers: { "CONTENT_TYPE" => "application/json" },
                                             without_csrf_token: true
      expect(response).to have_http_status(:unauthorized)
    end

    it "Google Calendar push notification" do
      GoogleCalendarChannel.create!(channel_id: "chan-c", resource_id: "res-c", expires_at: 1.week.from_now)
      headers = { "X-Goog-Channel-Id" => "chan-c", "X-Goog-Resource-Id" => "res-c", "X-Goog-Resource-State" => "exists" }
      expect { post "/google/calendar/webhook", headers: headers, without_csrf_token: true }
        .to have_enqueued_job(GoogleCalendarSyncJob)
      expect(response).to have_http_status(:ok)
    end

    describe "tap box (RfidController#card_number)" do
      include_context "with test cable adapter"

      let(:pi_reader) { create(:pi_reader, space: create(:space)) }
      let!(:rfid) { create(:rfid, user: user, mac_address: pi_reader.pi_mac_address) }

      it "a registered reader's JSON tap works" do
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address }.to_json,
                                    headers: { "CONTENT_TYPE" => "application/json" }, without_csrf_token: true
        expect(response).to have_http_status(:ok)
        expect(LabSession.where(user: user).count).to eq(1)
      end

      it "a registered reader's form-encoded tap works too (no cookie session, nothing to forge)" do
        post rfid_card_number_path, params: { rfid: rfid.card_number, mac_address: pi_reader.pi_mac_address },
                                    without_csrf_token: true
        expect(response).to have_http_status(:ok)
      end

      it "a tap riding on a staff cookie session is CSRF-checked like any form post" do
        log_in!(create(:user, :staff))
        post rfid_card_number_path, params: { rfid: rfid.card_number, space_id: pi_reader.space_id },
                                    without_csrf_token: true
        expect_stale_form_redirect(root_path)
        expect(LabSession.where(user: user).count).to eq(0)
      end
    end
  end
end
