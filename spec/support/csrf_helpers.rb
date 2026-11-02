# frozen_string_literal: true

# Forgery protection is ON in the test env (config/environments/test.rb), as in
# production. Specs send the token the way a browser does, so the real check
# runs on every non-GET request:
#
# - Request specs: every POST/PATCH/PUT/DELETE gets an X-CSRF-Token header (what
#   Turbo and src/csrf.js send) holding the CURRENT session's token. When the
#   session has none yet (a fresh session, or one just reset by sign-in or
#   sign-out), the helper first GETs a page, which stores one in the session,
#   exactly as a browser holds the page it submits from.
#   Opt out with `without_csrf_token: true` on the request, or by passing your
#   own token (an `authenticity_token` param or an X-CSRF-Token header); the
#   refusal paths are pinned in spec/requests/csrf_protection_request_spec.rb.
#
# - Controller specs (one controller, no pages rendered): the session is given a
#   token before each example and the request carries it in X-CSRF-Token.
#   `csrf: false` metadata leaves both out.
#
# System specs need nothing: the browser submits the real pages' tokens.
module CsrfRequestSpecHelpers
  CSRF_HEADER = "X-CSRF-Token"
  # A plain page that renders csrf_meta_tags and changes nothing.
  TOKEN_PAGE = "/terms_of_service"

  %i[post patch put delete].each do |verb|
    define_method(verb) do |path, **args|
      return super(path, **args.except(:without_csrf_token)) if args[:without_csrf_token] || csrf_token_given?(args)

      super(path, **args, headers: (args[:headers] || {}).merge(CSRF_HEADER => csrf_token))
    end
  end

  # The current session's token (fetching a page first if it has none).
  def csrf_token
    current_csrf_token || fetch_csrf_token
  end

  private

  def csrf_token_given?(args)
    headers = args[:headers] || {}
    params = args[:params]
    headers.key?(CSRF_HEADER) || headers.key?("HTTP_X_CSRF_TOKEN") ||
      (params.is_a?(Hash) && (params.key?(:authenticity_token) || params.key?("authenticity_token")))
  end

  # The token stored in the session the last response left in the cookie jar,
  # if that session cookie is still there (it expires after 7 days, so a spec
  # that travels in time starts a new session, as a browser would).
  def current_csrf_token
    return nil if integration_session.request.nil?
    session_cookie = cookies.get_cookie(Rails.application.config.session_options[:key])
    return nil if session_cookie.nil? || session_cookie.expired?

    session[:_csrf_token]
  end

  def fetch_csrf_token
    get(TOKEN_PAGE)
    session[:_csrf_token] || raise("#{TOKEN_PAGE} did not store a CSRF token in the session (#{response.status} #{response.body[0,300]})")
  end
end

module CsrfControllerSpecHelpers
  def self.token
    Base64.urlsafe_encode64(
      SecureRandom.random_bytes(ActionController::RequestForgeryProtection::AUTHENTICITY_TOKEN_LENGTH), padding: false
    )
  end
end

RSpec.configure do |config|
  config.include CsrfRequestSpecHelpers, type: :request

  config.before(:each, type: :controller) do |example|
    next if example.metadata[:csrf] == false

    token = CsrfControllerSpecHelpers.token
    session[:_csrf_token] = token
    request.headers[CsrfRequestSpecHelpers::CSRF_HEADER] = token
  end
end
