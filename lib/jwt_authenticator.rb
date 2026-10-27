# frozen_string_literal: true

require "jwt"

# The one rule for "is this Bearer JWT acceptable?", shared by
# ApplicationHelper#has_valid_jwt? and DirectUploadAuthentication (lib/, so it
# can be required by non-reloadable engine controllers).
# Returns the User the token authenticates, or nil.
#
# Rejected: bad signature / expired token, a `ver` that differs from the
# user's token_version (a token without `ver` counts as version 0), and users
# that are gone, soft-deleted, locked or inactive.
module JwtAuthenticator
  module_function

  def user_for(authorization_header)
    token = authorization_header.to_s.split(" ")[1]
    return nil if token.blank?

    payload, = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: "HS256" })
    user = User.find_by(id: payload["user_id"])
    return nil if user.nil? || user.deleted?
    return nil unless payload.fetch("ver", 0) == user.token_version
    return nil if user.locked? && (user.locked_until.nil? || user.locked_until > Time.current)
    return nil if user.active == false

    user
  rescue JWT::DecodeError
    nil
  end
end

# The matching rule for cookie sessions: the session's stored token_version
# (absent = 0, a session from before the column existed) must equal the user's,
# and the user must not be deactivated. Used by ApplicationHelper#session_user
# and DirectUploadAuthentication.
module SessionAuthenticator
  module_function

  def valid_for?(session, user)
    return false if user.nil?

    session.fetch(:token_version, 0) == user.token_version && user.active != false
  end
end
