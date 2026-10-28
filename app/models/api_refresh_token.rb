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

  # A rotated token was presented again within GRACE of its rotation: almost
  # certainly a second tab racing the first, not theft. See #rotate!.
  class RefreshInProgress < StandardError; end

  GRACE = 30.seconds

  attr_reader :raw_token

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

  # The record for a presented raw token (any state), or nil. The rules for what
  # may be done with it live in #rotate!.
  def self.find_by_raw(raw)
    return nil unless raw.is_a?(String) && raw.present?

    find_by(token_digest: digest(raw))
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

  # Always ORDER BY family_id, id: the one global lock order (revoke_all_for! locks
  # many families, rotate!/revoke_family! one), so no two lockers can deadlock.
  def self.lock_family!(family_id)
    where(family_id: family_id).order(:family_id, :id).lock.pluck(:id)
  end

  PRUNE_AFTER = 7.days

  # Deletes rows that can no longer matter: past their own expiry or the family cap
  # by more than PRUNE_AFTER, or revoked more than PRUNE_AFTER ago. Safe for the cap
  # because every row carries family_expires_at. Returns the number of rows deleted.
  # A pruned rotated token is simply unknown if replayed (401), same as a live replay minus the family revoke.
  def self.prune!(now: Time.current)
    cutoff = now - PRUNE_AFTER
    where("expires_at < :c OR family_expires_at < :c OR revoked_at < :c", c: cutoff).delete_all
  end

  # Every refresh token of a user (token_version bumps, deactivation). Locks every
  # family of the user first (one statement, ORDER BY family_id, id, the same order as
  # lock_family!), so a rotation in flight finishes first and its successor is seen
  # by the UPDATE, which is a new statement.
  def self.revoke_all_for!(user_id, now: Time.current)
    transaction do
      where(user_id: user_id).order(:family_id, :id).lock.pluck(:id)
      where(user_id: user_id, revoked_at: nil).update_all(revoked_at: now)
    end
  end

  def revoked? = revoked_at.present?
  def expired?(now = Time.current) = expires_at <= now

  def usable?(now = Time.current)
    !revoked? && !expired?(now) && family_expires_at > now && AuthEligibility.allowed?(user) && token_version == user.token_version
  end

  # Revokes this token and issues its successor in the same family, under the
  # family lock. Returns the successor (raw value on #raw_token), or nil when this
  # token is not usable (unknown state, expired, stale token_version, ineligible
  # user, revoked by logout).
  #
  # The one place the replay rules live. A token that was already rotated
  # (revoked WITH a successor) and is presented again:
  # * within GRACE of its rotation, while the family is still live: raises
  #   RefreshInProgress and revokes nothing. The caller should retry with the token
  #   the winning request received (several browser tabs refreshing at once);
  # * later (or once the family is dead): theft. The family is revoked (after the
  #   transaction, so the revoke is not rolled back) and nil is returned.
  def rotate!(user_agent: nil)
    outcome = nil
    successor = transaction do
      self.class.lock_family!(family_id)
      lock! # reloads the row AND drops the cached user, so usable? below sees the CURRENT token_version/state
      if revoked?
        outcome = replay_outcome if replaced_by_id.present?
        next nil
      end
      next nil unless usable?

      now = Time.current
      fresh = self.class.issue!(user, family: family_id, family_expires_at: family_expires_at, user_agent: user_agent, now: now)
      update!(revoked_at: now, replaced_by_id: fresh.id, last_used_at: now)
      fresh
    end
    raise RefreshInProgress if outcome == :in_progress

    self.class.revoke_family!(family_id) if outcome == :theft
    successor
  rescue ActiveRecord::RecordNotFound
    nil # pruned (expired or revoked long ago) between lookup and lock
  end

  def revoke_family! = self.class.revoke_family!(family_id)

  private

  def replay_outcome
    in_window = revoked_at > GRACE.ago
    family_live = self.class.where(family_id: family_id, revoked_at: nil).exists?
    in_window && family_live ? :in_progress : :theft
  end
end
