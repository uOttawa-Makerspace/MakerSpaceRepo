# frozen_string_literal: true

class ApplicationController < ActionController::Base
  rescue_from ActionController::ParameterMissing, with: :parameter_missing

  # CSRF (INF-01): every non-GET request must carry the session's token (Rails
  # helpers and Turbo add it; fetch() calls use src/csrf.js). A GET answered
  # with JavaScript is only served to same-origin XHR (the cross-origin JS guard
  # that comes with this check).
  #
  # The one exemption, legacy_json_request?, is for the React apps that still
  # call these HTML-side endpoints with the cookie session (MakerRepoApp's
  # src/utils/HTTPRequests.tsx, until it moves to /api/v1, which is Bearer-only
  # and has no CSRF module). A request qualifies only when its body is
  # declared application/json AND it asks for JSON. A cross-site page cannot
  # send that Content-Type without a CORS preflight, which only the origins in
  # config/initializers/cors.rb pass; a plain HTML form (urlencoded, multipart
  # or text/plain) posting to /foo.json or ?format=json is still checked.
  # Endpoints called by external systems skip the check in their own
  # controller and authenticate the caller themselves (CustomWebhooksController,
  # GoogleCalendarController, RfidController#card_number).
  protect_from_forgery with: :exception
  skip_forgery_protection if: :legacy_json_request?
  include ApplicationHelper
  require "zip"
  include Pagy::Method
  around_action :switch_locale
  before_action :set_last_seen_at,
                if:
                  proc {
                    signed_in? &&
                      (
                        current_user.last_seen_at.nil? ||
                          current_user.last_seen_at < 15.minutes.ago
                      )
                  }
  helper_method :current_order

  # I18n.locale is thread-global, so scope it to the request (with_locale
  # restores it afterwards) and ignore unsupported values instead of raising
  # I18n::InvalidLocale.
  def switch_locale(&action)
    available = I18n.available_locales.map(&:to_s)
    candidate = [params[:locale], session[:locale]].find { |l| l.to_s.presence_in(available) }
    locale = candidate ? candidate.to_s.to_sym : I18n.default_locale
    session[:locale] = locale
    I18n.with_locale(locale, &action)
  end

  def current_order
    session_order = Order.find_by(id: session[:order_id]) unless session[:order_id].nil?
    if session_order.present? && current_user.id.present? &&
         session_order.user_id == current_user.id &&
         session_order.order_status&.name.eql?("In progress")
      return session_order
    end
    session[:order_id] = nil

    if current_user.orders.last.present? &&
         current_user.orders.last.order_status.name.eql?("In progress")
      current_user.orders.last
    else
      Order.new
    end
  end

  private

  def legacy_json_request?
    request.media_type == Mime[:json].to_s && request.format.json?
  end

  def set_last_seen_at
    current_user.update_attribute(:last_seen_at, Time.current)
    session[:last_seen_at] = Time.current
  end

  def signed_in
    return if signed_in?

    respond_to do |format|
      format.html { redirect_to login_path(back_to: login_back_to) }
      format.js { render js: "window.location.href = '#{login_path}'" }
      format.json { render json: "redirect" }
    end
  end

  # Where to send the user after logging in. Only GET/HEAD URLs can be revisited;
  # a POST/PATCH/DELETE target would 404 as a GET, so for those fall back to the
  # referring page when it is on this host, otherwise nothing.
  def login_back_to
    if request.get? || request.head?
      # On the login page itself the real destination is the one it was given.
      return login_page_path?(request.path) ? safe_back_to : request.fullpath
    end

    # A failed login re-renders the login view at POST /login_authentication.
    return safe_back_to if login_page_path?(request.path)

    referer = URI.parse(request.referer.to_s)
    return unless referer.is_a?(URI::HTTP) && referer.host.present? && referer.host == request.host

    path = referer.request_uri
    path unless login_page_path?(URI.parse(path).path)
  rescue URI::InvalidURIError
    nil
  end

  LOGIN_PAGE_PATHS = %w[/login /login_authentication].freeze

  # /login and /login_authentication (POST-only; a failed login renders at that
  # URL) normalised without trailing slash or format extension.
  def login_page_path?(path)
    LOGIN_PAGE_PATHS.include?(path.to_s.downcase.sub(/\.\w+\z/, "").chomp("/"))
  end

  # Same-site paths only: url_from drops foreign hosts, and protocol-relative
  # or backslash forms ("//evil.com", "/\\evil.com") are refused outright.
  def safe_back_to
    target = params[:back_to].to_s
    return if target.start_with?("//", "/\\")

    safe = url_from(target)
    safe unless safe && login_page_path?(URI.parse(safe).path)
  rescue URI::InvalidURIError
    nil
  end
  helper_method :login_back_to, :safe_back_to

  def parameter_missing(exception)
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message }
      format.json { render json: { error: exception.message }, status: 400 }
    end
  end
end
