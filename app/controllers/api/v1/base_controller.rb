# frozen_string_literal: true

require Rails.root.join("lib/jwt_authenticator")

module Api
  module V1
    # Base of every /api/v1 controller. ActionController::API: no cookies, no
    # flash, no CSRF protection (those modules are not included), and the session
    # is switched off below, so a response can never carry a Set-Cookie header.
    # Auth is `Authorization: Bearer <access JWT>` only (ApiAccessToken ->
    # AuthEligibility: deleted, inactive and stale-version users are refused). The
    # session is never read or written.
    #
    # Errors are always `{error: {code:, message:, fields?:}}` with a real status:
    # 400 bad_request, 401 unauthenticated, 403 forbidden, 404 not_found,
    # 422 validation_failed / parameter_missing, 423 account_locked, 429 rate_limited.
    class BaseController < ActionController::API
      before_action :disable_session
      before_action :no_store
      # Parse the body up front so malformed JSON is a rescued 400 even for actions that never read params.
      before_action { request.request_parameters }

      rescue_from ActiveRecord::RecordNotFound do |_e|
        render_error(:not_found, "Not found", status: :not_found)
      end
      rescue_from ActionController::ParameterMissing do |e|
        render_error(:parameter_missing, "Missing parameter: #{e.param}", status: :unprocessable_content,
                     fields: { e.param => ["is required"] })
      end
      rescue_from ActiveRecord::RecordInvalid do |e|
        render_validation_errors(e.record)
      end
      rescue_from ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError do |_e|
        render_error(:bad_request, "Malformed request", status: :bad_request)
      end

      # Unknown /api/v1 paths (the catch-all route at the end of the namespace).
      def route_not_found
        render_error(:not_found, "Not found", status: :not_found)
      end

      private

      def current_user
        return @current_user if defined?(@current_user)

        @current_user = ApiAccessToken.user_for(request.headers["Authorization"])
      end

      def signed_in?
        current_user.present?
      end

      def authenticate!
        return if signed_in?

        response.set_header("WWW-Authenticate", 'Bearer realm="makerepo"')
        render_error(:unauthenticated, "Authentication required", status: :unauthorized)
      end

      def require_staff!
        authenticate!
        return if performed? || current_user.staff?

        render_error(:forbidden, "Not allowed", status: :forbidden)
      end

      def require_admin!
        authenticate!
        return if performed? || current_user.admin?

        render_error(:forbidden, "Not allowed", status: :forbidden)
      end

      def render_error(code, message, status:, fields: nil, **extra)
        body = { code: code.to_s, message: message }
        body[:fields] = fields if fields
        render json: { error: body.merge(extra) }, status: status
      end

      def render_validation_errors(record)
        render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                     fields: record.errors.to_hash)
      end

      def rate_limited
        render_error(:rate_limited, "Too many requests", status: :too_many_requests)
      end

      def disable_session
        request.session_options[:skip] = true
      end

      def no_store
        response.set_header("Cache-Control", "no-store")
      end
    end
  end
end
