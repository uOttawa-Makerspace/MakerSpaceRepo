# frozen_string_literal: true

# The pages Rails shows when a request fails outside any controller rescue
# (config.exceptions_app routes /404, /422 and /500 here). It is kept apart from
# ApplicationController on purpose: no session user, no database, no site layout,
# so a failure of any of those cannot break the error page itself. It is a third
# controller base, so it takes RateLimitStore like the other two.
class ErrorsController < ActionController::Base
  include RateLimitStore
  include ErrorReporting
  include RequestLocale

  PAGES = { "404" => :not_found, "422" => :unprocessable, "500" => :unexpected }.freeze

  # The original request may be a POST: there is no form to protect here.
  skip_forgery_protection
  layout "error"
  around_action { |_controller, action| with_request_locale(&action) }

  # Never raises on the request format: a malformed or unusual Accept header gets the
  # HTML page, JSON only when the client asks for it, and an empty body for anything else
  # (an image or other asset request).
  def show
    page = PAGES.fetch(params[:code])
    status = params[:code].to_i
    case wanted_format
    when :json then render json: { error: page_message(page), reference: error_reference }, status: status
    when :html then render page, status: status, formats: :html
    else head status
    end
  end

  private

  # HTML or JSON, whichever the client lists first (q-values and order honoured), JSON
  # for ?format=json, HTML for a blank, "*/*" or unreadable Accept header, and :other
  # when the client accepts neither (an image or other asset request).
  def wanted_format
    return :json if params[:format].to_s == "json"

    accepted = accepted_types
    return :html if accepted.empty?

    format_of(accepted.find { |type| type.html? || type.json? })
  rescue Mime::Type::InvalidMimeType, ArgumentError, ActionController::BadRequest
    :html
  end

  def format_of(type)
    return :other unless type

    type.json? ? :json : :html
  end

  def accepted_types
    Mime::Type.parse(request.headers["Accept"].to_s.scrub(""))
  end

  def page_message(page)
    page == :unexpected ? unexpected_error_message : I18n.t("errors.generic.#{page}")
  end
end
