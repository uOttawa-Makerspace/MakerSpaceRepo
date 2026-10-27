# frozen_string_literal: true

require "jwt"

# The one rule for "is this Bearer JWT acceptable?", shared by
# ApplicationHelper#has_valid_jwt?. Other Bearer entry points (e.g. direct
# uploads) should call it instead of decoding tokens themselves.
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
