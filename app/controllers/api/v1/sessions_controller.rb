# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/session.md.
    class SessionsController < BaseController
      SUPPORT_EMAIL = ::SessionsController::SUPPORT_EMAIL

      # Same budget as the HTML login and SAML sign-in (one limit, window and
      # cache key per IP), so the surfaces cannot be alternated to multiply it.
      rate_limit(**::SessionsController::SIGN_IN_RATE_LIMIT, only: :create, with: :rate_limited)
      # Refresh tokens are 256-bit random, so this only bounds DB work.
      rate_limit to: 120, within: 1.minute, only: :refresh, scope: "api-session-refresh", with: :rate_limited

      before_action :authenticate!, only: :show

      def create
        login = params.require(:login).to_s
        password = params.require(:password).to_s
        result = CredentialAuthenticator.call(login, password)

        case result.refusal
        when :locked
          render_locked(result.candidate)
        when :inactive
          # :inactive and the error code account_inactive are the external contract; both mean
          # deactivated (users.deactivated_at).
          render_error(:account_inactive, I18n.t("sessions.account_deactivated", support_email: SUPPORT_EMAIL),
                       status: :forbidden, support_email: SUPPORT_EMAIL)
        when :unconfirmed
          render_error(:account_unconfirmed, "Please confirm your account before logging in.", status: :forbidden)
        else
          result.user ? render_new_session(result.user) : render_bad_credentials(result.candidate)
        end
      end

      def refresh
        presented = ApiRefreshToken.find_by_raw(refresh_token_param)
        successor = presented&.rotate!(user_agent: request.user_agent)
        return render_invalid_refresh_token unless successor

        render json: token_pair(presented.user, successor), status: :ok
      rescue ApiRefreshToken::RefreshInProgress
        render_error(:refresh_in_progress,
                     "This refresh token was just used by another request; retry with the newest stored token",
                     status: :conflict)
      end

      def show
        render json: { user: UserSerializer.call(current_user) }
      end

      # Idempotent: an unknown, expired or already revoked token is still a 204.
      def destroy
        raw = params[:refresh_token].presence || request.headers["X-Refresh-Token"].presence
        ApiRefreshToken.find_by(token_digest: ApiRefreshToken.digest(raw))&.revoke_family! if raw.is_a?(String)
        head :no_content
      end

      private

      def refresh_token_param
        token = params.require(:refresh_token)
        token.is_a?(String) ? token : nil
      end

      def render_new_session(user)
        user.update_column(:last_signed_in_time, Time.current)
        refresh = ApiRefreshToken.issue!(user, user_agent: request.user_agent)
        render json: token_pair(user, refresh), status: :created
      end

      def token_pair(user, refresh)
        access, expires_at = ApiAccessToken.issue(user)
        {
          access_token: access,
          access_token_expires_at: expires_at.utc.iso8601,
          refresh_token: refresh.raw_token,
          user: UserSerializer.call(user)
        }
      end

      def render_locked(user)
        render_error(:account_locked,
                     "Your account has been locked due to too many failed login attempts. Please contact an administrator at #{SUPPORT_EMAIL} to unlock your account#{CredentialAuthenticator.lock_wait_suffix(user)}.",
                     status: :locked, support_email: SUPPORT_EMAIL)
      end

      # Unknown login and wrong password answer identically (no account
      # enumeration). The attempt that reaches the limit answers as locked.
      def render_bad_credentials(user)
        return render_locked(user) if user && user.auth_attempts >= User::MAX_AUTH_ATTEMPTS

        render_error(:invalid_credentials, "Invalid login or password", status: :unauthorized)
      end

      def render_invalid_refresh_token
        render_error(:invalid_refresh_token, "Refresh token is invalid, expired or revoked", status: :unauthorized)
      end
    end
  end
end
