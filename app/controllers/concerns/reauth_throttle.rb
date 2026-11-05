# frozen_string_literal: true

# One budget for every place a signed-in user re-types their current password
# (change_password, change_email, an admin deleting an account). Each submitted password is
# counted ATOMICALLY (RateLimitCounter, per user and per credential generation) BEFORE it is
# verified, so parallel guesses cannot all slip under the limit; a correct one clears the
# count. A blank one is a validation error, not a guess, and is not counted. Going over ends
# every credential of the user (cookie session, JWT, refresh tokens: token_version bump)
# without running bcrypt: the session is ended, the account is not locked, and signing in
# again starts a fresh budget (a new token_version is a new key). It never touches the login
# lockout (auth_attempts/locked).
#
# The including controller defines `submitted_current_password` (what the action was given)
# and must have @user set to the signed-in user before limit_reauth_attempts runs.
module ReauthThrottle
  extend ActiveSupport::Concern

  REAUTH_MAX_ATTEMPTS = 5
  REAUTH_WINDOW = 15.minutes
  REAUTH_LIMIT_ALERT =
    'Too many incorrect current-password attempts. You have been signed out for your security; ' \
    'please sign in again to continue.'

  private

  def current_password_submitted?
    submitted_current_password.present?
  end

  # Counts the attempt and, when it is over the limit, ends every credential of the
  # user (User#count_reauth_attempt!: one transaction, fail closed: if anything raises
  # the attempt is not counted, nothing is bumped, and the error propagates BEFORE any
  # password is checked). Over the limit the request is signed out whether or not it
  # was the one that bumped (a racing request, or a vanished account, just signs out).
  def limit_reauth_attempts
    count = @user.count_reauth_attempt!(max: REAUTH_MAX_ATTEMPTS, window: REAUTH_WINDOW)
    return if count <= REAUTH_MAX_ATTEMPTS

    sign_out
    redirect_to login_path, alert: REAUTH_LIMIT_ALERT
  end
end
