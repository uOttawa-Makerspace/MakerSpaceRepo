# frozen_string_literal: true

require "digest"
require Rails.root.join("lib/jwt_authenticator")

# Revocable, rotating refresh token for /api/v1 (see doc/api/v1/session.md).
#
# Only the SHA-256 digest of the 32-byte random token is stored; the raw value
# exists once, in the response that issued it (#raw_token on the issued record).
# Lifetime: 30 days, sliding on each rotation, but never past 90 days from the
# first login of the family (FAMILY_CAP; stored as family_expires_at on every token). A family is the chain of tokens
# descending from one login (one device/session).
#
# A token is usable only if it is not revoked, not expired, carries the user's
# CURRENT token_version, and the user is eligible (AuthEligibility). Presenting a
# token that was already rotated (revoked WITH a successor) is treated as theft:
# the whole family is revoked. A token revoked by logout has no successor, so
# replaying it is just refused.
class ApiRefreshToken < ApplicationRecord
  TTL = 30.days
  FAMILY_CAP = 90.days

  belongs_to :user, -> { unscope(where: :deleted) }, inverse_of: false
  belongs_to :replaced_by, class_name: "ApiRefreshToken", optional: true

  attr_reader :raw_token

  scope :live, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  # Issues a token for `user`. With `family:` it continues that family (rotation).
  # The raw value is on the returned record's #raw_token.
  # A new family's absolute cap is now + FAMILY_CAP; a continued family must pass
  # the cap it already has (family_expires_at:), copied from the token it replaces.
  def self.issue!(user, family: nil, family_expires_at: nil, user_agent: nil, now: Time.current)
    raise ArgumentError, "family_expires_at is required with family" if family && family_expires_at.nil?

    family_id = family || SecureRandom.uuid
    cap = family_expires_at || (now + FAMILY_CAP)
    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: digest(raw),
      family_id: family_id,
      family_expires_at: cap,
      token_version: user.token_version,
      expires_at: [now + TTL, cap].min,
      user_agent: user_agent.to_s.truncate(255).presence,
      created_at: now,
      last_used_at: now
    )
    record.instance_variable_set(:@raw_token, raw)
    record
  end

  # The usable record for a raw token, or nil. Side effect: replaying a rotated
  # token revokes its family.
  def self.authenticate(raw)
    return nil if raw.blank? || !raw.is_a?(String)

    record = find_by(token_digest: digest(raw))
    return nil unless record

    if record.revoked?
      revoke_family!(record.family_id) if record.replaced_by_id
      return nil
    end
    return nil unless record.usable?

    record
  end

  # Rotation and family revocation serialize on the FAMILY: both first lock every
  # row of the family (ORDER BY id, so two lockers cannot deadlock). The UPDATE
  # below is a new statement, so it sees a successor that a rotation inserted while
  # this call waited for the lock; without the lock it would only touch the rows of
  # its own snapshot and miss it (logout racing a refresh would leave a live token).
  def self.revoke_family!(family_id, now: Time.current)
    transaction do
      lock_family!(family_id)
      where(family_id: family_id, revoked_at: nil).update_all(revoked_at: now)
    end
  end

  def self.lock_family!(family_id)
    where(family_id: family_id).order(:id).lock.pluck(:id)
  end

  # Every refresh token of a user (token_version bumps).
  def self.revoke_all_for!(user_id, now: Time.current)
    where(user_id: user_id, revoked_at: nil).update_all(revoked_at: now)
  end

  def revoked? = revoked_at.present?
  def expired?(now = Time.current) = expires_at <= now

  def usable?(now = Time.current)
    !revoked? && !expired?(now) && family_expires_at > now && AuthEligibility.allowed?(user) && token_version == user.token_version
  end

  # Revokes this token and issues its successor in the same family, under a row
  # lock. Returns the successor (raw value on #raw_token), or nil when this token
  # is no longer usable. If a concurrent request rotated it first, that is a
  # replay of a rotated token: the family is revoked (after the transaction, so
  # the revoke is not rolled back).
  def rotate!(user_agent: nil)
    replay = false
    successor = transaction do
      self.class.lock_family!(family_id)
      lock!
      if revoked?
        replay = replaced_by_id.present?
        next nil
      end
      next nil unless usable?

      now = Time.current
      fresh = self.class.issue!(user, family: family_id, family_expires_at: family_expires_at, user_agent: user_agent, now: now)
      update!(revoked_at: now, replaced_by_id: fresh.id, last_used_at: now)
      fresh
    end
    self.class.revoke_family!(family_id) if replay
    successor
  end

  def revoke_family! = self.class.revoke_family!(family_id)
end
