# frozen_string_literal: true

require "jwt"

# Who may stay signed in, whatever the credential (Bearer JWT or cookie
# session): present, not soft-deleted, not deactivated. Locks are NOT looked at:
# a lock (the timed brute-force lockout or an admin lock) blocks NEW logins only
# (ApplicationHelper#sign_in). An admin lock ends existing sessions and JWTs
# permanently by bumping token_version (User#admin_lock!),
# which no later change of the lock fields can undo.
module AuthEligibility
  module_function

  def allowed?(user)
    return false if user.nil? || user.deleted?

    user.deactivated_at.nil?
  end
end

# The one rule for "is this Bearer JWT acceptable?", shared by
# ApplicationHelper#has_valid_jwt? and DirectUploadAuthentication (lib/, so it
# can be required by non-reloadable engine controllers).
# Returns the User the token authenticates, or nil.
#
# Rejected: bad signature / expired token, any token with a `typ` claim, a `ver` that differs from the
# user's token_version (a token without `ver` counts as version 0), and users
# that are gone, soft-deleted or inactive (AuthEligibility). Locks are not looked
# at: an admin lock revokes tokens by bumping token_version; a timed lockout
# blocks new logins only.
module JwtAuthenticator
  module_function

  def user_for(authorization_header)
    token = authorization_header.to_s.split(" ")[1]
    return nil if token.blank?

    payload, = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: "HS256" })
    # Legacy tokens (User#token) never carry `typ`. Any typed token (the /api/v1
    # access token) is API-only, even when both are signed with the same key.
    return nil if payload.key?("typ")

    user = User.find_by(id: payload["user_id"])
    return nil unless AuthEligibility.allowed?(user)
    return nil unless payload.fetch("ver", 0) == user.token_version

    user
  rescue JWT::DecodeError
    nil
  end
end

# Access tokens for /api/v1 (Api::V1::BaseController). Short-lived (15 min),
# HS256, claims user_id / exp / ver (= users.token_version) / typ ("access").
# Differences from the legacy 14-day token (User#token) that JwtAuthenticator
# accepts: the "Bearer" scheme word is checked, `typ` must be "access", and the
# signing secret is dedicated when credentials define one.
# A token_version bump (password change/reset, admin lock, soft delete) kills
# every access token through `ver`, same as the legacy one.
module ApiAccessToken
  TTL = 15.minutes
  TYPE = "access"

  module_function

  # credentials.jwt.secret when configured (add it to the credentials to split the
  # API signing key from secret_key_base); secret_key_base otherwise, so nothing
  # needs to be deployed for this to work.
  def secret
    Rails.application.credentials.dig(:jwt, :secret).presence || Rails.application.credentials.secret_key_base
  end

  # Returns [jwt, expires_at].
  def issue(user, now: Time.current)
    expires_at = now + TTL
    jwt = JWT.encode(
      { user_id: user.id, ver: user.token_version, typ: TYPE, iat: now.to_i, exp: expires_at.to_i },
      secret,
      "HS256"
    )
    [jwt, expires_at]
  end

  # The User an `Authorization: Bearer <access>` header authenticates, or nil.
  def user_for(authorization_header)
    scheme, token, extra = authorization_header.to_s.split(" ")
    return nil unless scheme.to_s.casecmp?("Bearer") && token.present? && extra.nil?

    payload, = JWT.decode(token, secret, true, { algorithm: "HS256", verify_expiration: true })
    return nil unless payload["typ"] == TYPE

    user = User.find_by(id: payload["user_id"])
    return nil unless AuthEligibility.allowed?(user)
    return nil unless payload["ver"] == user.token_version

    user
  rescue JWT::DecodeError
    nil
  end
end

# The one rule for "is this cookie session still valid?": not idle-expired
# (the 72h sliding window), the session's stored token_version (absent = 0, a
# session from before the column existed) equal to the user's, and the user
# eligible (AuthEligibility). Every place that resolves a session user goes
# through valid_for?: ApplicationHelper#session_user (every controller, SAML
# included), ApplicationCable::Connection and DirectUploadAuthentication. So no
# controller can skip the idle expiry (INF-04). session_user also extends the
# window of a valid session (touch), so activity on any controller counts.
module SessionAuthenticator
  IDLE_TIMEOUT = 72.hours
  # The window is rewritten at most this often, not on every request (each
  # rewrite is a session write, i.e. a new cookie).
  TOUCH_INTERVAL = 5.minutes

  module_function

  def valid_for?(session, user)
    return false if expired?(session)

    AuthEligibility.allowed?(user) && session.fetch(:token_version, 0) == user.token_version
  end

  # Starts a full idle window (sign-in).
  def start(session)
    session[:expires_at] = IDLE_TIMEOUT.from_now
  end

  # Extends the window of a session already found valid (ApplicationHelper#
  # session_user; never called for an expired one), at most every TOUCH_INTERVAL.
  def touch(session)
    return if session[:expires_at] && seconds_left(session) > (IDLE_TIMEOUT - TOUCH_INTERVAL).to_i

    start(session)
  end

  # A session without the key has a full window.
  def seconds_left(session)
    expire_time = session[:expires_at] || IDLE_TIMEOUT.from_now
    (expire_time.to_time - Time.zone.now).to_i
  end

  def expired?(session)
    seconds_left(session) <= 0
  end
end
