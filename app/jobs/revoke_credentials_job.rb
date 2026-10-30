# frozen_string_literal: true

# Ends every credential of a user whose inline revocation failed (re-auth
# exhaustion in UsersController#limit_reauth_attempts), so the tokens do not stay
# live just because the attacker never comes back. It runs the same compare-and-set
# bump from the token_version the attempts were counted under: the first run that
# matches revokes everything, any later or duplicate run matches nothing and does
# nothing, so retries and double enqueues are safe.
class RevokeCredentialsJob < ApplicationJob
  queue_as :default

  # Transient database trouble (deadlock, lock timeout, dropped connection).
  retry_on ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished,
           wait: :polynomially_longer, attempts: 8

  # A hard-deleted user has no credentials left to revoke.
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id, from_version)
    User.find(user_id).bump_token_version!(from_version: from_version)
  end
end
