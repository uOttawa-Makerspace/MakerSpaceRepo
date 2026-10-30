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
# credentials, or success), :locked, :inactive or :unconfirmed. Result#candidate is
# the account the login named (nil if none), fresh after a failed attempt, so
# callers can word the refusal (lock wait, attempts) without looking it up again.
class CredentialAuthenticator
  Result = Struct.new(:user, :refusal, :candidate, keyword_init: true)

  def self.call(login, password)
    candidate = User.username_or_email(login)
    if candidate&.locked?
      return Result.new(refusal: :locked, candidate: candidate) if candidate.lock_in_effect?

      candidate.update_columns(locked: false, auth_attempts: 0) # the timed lockout has lapsed
    end

    user = User.authenticate(login, password)
    return Result.new(refusal: :inactive, candidate: user) if user&.active == false
    return Result.new(refusal: :unconfirmed, candidate: user) if user && !user.confirmed?
    return Result.new(user: user, candidate: user) if user

    # Bad credentials: User.authenticate counted the failure on its own instance.
    Result.new(candidate: refetch(candidate))
  end

  # Re-authentication of a signed-in user before a credential change (change
  # password, change email): the login's rules and bookkeeping for that account.
  # A lock in effect refuses before the password is looked at (a lapsed timed
  # lockout is cleared); a wrong password counts on auth_attempts and locks the
  # account at User::MAX_AUTH_ATTEMPTS (timed lockout + unlock email), exactly as
  # failed logins do and on the same counter; the right one resets the counter.
  # Returns :ok, :invalid or :locked.
  def self.verify_current_password(user, password)
    if user.locked?
      return :locked if user.lock_in_effect?

      user.update_columns(locked: false, auth_attempts: 0) # the timed lockout has lapsed
    end

    if user.authenticate_password(password.to_s)
      user.reset_auth_attempts!
      :ok
    else
      user.record_failed_attempt!
      user.lock_in_effect? ? :locked : :invalid
    end
  end

  # The message for a refused current-password check.
  def self.current_password_alert(user, verdict)
    return "Incorrect current password." unless verdict == :locked

    "Your account is locked after too many incorrect passwords. Use the link we emailed you to unlock it" \
      "#{lock_wait_suffix(user)}."
  end

  # The failed attempt was counted on another instance: re-read the row, bypassing the
  # query cache. A user deleted (hard or soft) since the lookup is no candidate at all,
  # so the caller answers plain invalid credentials.
  def self.refetch(candidate)
    return nil unless candidate

    fresh = User.uncached { User.unscoped.find_by(id: candidate.id) }
    fresh unless fresh.nil? || fresh.deleted
  end
  private_class_method :refetch

  # " or wait 5 minutes" for a timed (brute-force) lockout; nothing for an admin
  # lock, which has no meaningful wait (99 years, or no end).
  def self.lock_wait_suffix(user, verb = "wait")
    return "" unless user&.timed_lockout?

    " or #{verb} #{ActionController::Base.helpers.distance_of_time_in_words(user.locked_until, Time.current)}"
  end
end
