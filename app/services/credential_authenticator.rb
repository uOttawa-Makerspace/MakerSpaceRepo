# frozen_string_literal: true

# The one login rule behind every password sign-in (HTML/JSON/SAML through
# ApplicationHelper#sign_in, and /api/v1/session): a lock still in effect is
# refused BEFORE the password is looked at (so a locked account cannot be probed
# or have its lock rewritten by failed attempts; a lapsed timed lockout is
# cleared), then the password is checked with the failed-attempt bookkeeping
# (User.authenticate), then a deactivated account (D-I03) and an unconfirmed one
# are refused. No session or token work happens here; callers do their own.
#
# Result#user is the authenticated User or nil; Result#refusal is nil (bad
# credentials, or success), :locked, :inactive or :unconfirmed.
class CredentialAuthenticator
  Result = Struct.new(:user, :refusal, keyword_init: true)

  def self.call(login, password)
    candidate = User.username_or_email(login)
    if candidate&.locked?
      return Result.new(refusal: :locked) if candidate.lock_in_effect?

      candidate.update_columns(locked: false, auth_attempts: 0) # the timed lockout has lapsed
    end

    user = User.authenticate(login, password)
    return Result.new(refusal: :inactive) if user&.active == false
    return Result.new(refusal: :unconfirmed) if user && !user.confirmed?

    Result.new(user: user)
  end

  # " or wait 5 minutes" for a timed (brute-force) lockout; nothing for an admin
  # lock, which has no meaningful wait (99 years, or no end).
  def self.lock_wait_suffix(user, verb = "wait")
    return "" unless user&.timed_lockout?

    " or #{verb} #{ActionController::Base.helpers.distance_of_time_in_words(user.locked_until, Time.current)}"
  end
end
