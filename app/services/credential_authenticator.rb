# frozen_string_literal: true

# The one login rule behind every password sign-in (HTML/JSON/SAML through
# ApplicationHelper#sign_in, and /api/v1/session): while a lock is in effect the
# password is not compared at all and the answer is plain bad credentials, the same as
# for a wrong password or an unknown login (so a locked account neither confirms a
# guess nor shows that it exists, and its lock and count are left alone; a lapsed timed
# lockout is cleared). Otherwise the password is checked with the failed-attempt
# bookkeeping (User.authenticate), then a deactivated account and an unconfirmed one are
# refused. A login that matches no account (or a locked one) still runs one dummy bcrypt
# comparison, so it costs the same as a real check. No session or token work happens
# here; callers do their own.
#
# Result#user is the authenticated User or nil; Result#refusal is nil (bad
# credentials, or success), :inactive (deactivated: the name is a contract kept for the API
# error code account_inactive) or :unconfirmed. Result#candidate is
# the account the login named (nil if none, and nil for bad credentials on a locked account),
# fresh after a failed attempt, so callers can word a refusal without looking it up again.
class CredentialAuthenticator
  Result = Struct.new(:user, :refusal, :candidate, keyword_init: true)

  def self.call(login, password)
    candidate = User.username_or_email(login)
    if candidate&.locked?
      if candidate.lock_in_effect?
        compare_dummy(password)
        return Result.new
      end

      candidate.update_columns(locked: false, auth_attempts: 0) # the timed lockout has lapsed
    end
    compare_dummy(password) if candidate.nil?

    user = User.authenticate(login, password)
    return Result.new(refusal: :inactive, candidate: user) if user&.deactivated_at
    return Result.new(refusal: :unconfirmed, candidate: user) if user && !user.confirmed?
    return Result.new(user: user, candidate: user) if user

    # Bad credentials: User.authenticate counted the failure on its own instance.
    Result.new(candidate: refetch(candidate))
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

  # One bcrypt comparison against a fixed hash made once at the app's cost.
  def self.compare_dummy(password)
    @dummy_password ||= BCrypt::Password.create(SecureRandom.hex(16))
    @dummy_password == password.to_s
  end
  private_class_method :compare_dummy
end
