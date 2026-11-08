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

  def show
    page = PAGES.fetch(params[:code])
    status = params[:code].to_i
    respond_to do |format|
      format.html { render page, status: status }
      format.json { render json: { error: page_message(page), reference: error_reference }, status: status }
      format.any { head status }
    end
  end

  private

  def page_message(page)
    page == :unexpected ? unexpected_error_message : I18n.t("errors.generic.#{page}")
  end
end
