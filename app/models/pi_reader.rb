# frozen_string_literal: true

class PiReader < ApplicationRecord
  belongs_to :space, optional: true

  before_validation :normalize_mac_address, on: :create
  validates :pi_mac_address, presence: true, on: :create
  validate :mac_address_not_registered, on: :create
  # Only when the identifier is being written. Rows already stored are never re-judged by an unrelated
  # edit: the bound is NOT enforced on them (checked against the production dump of 2026-08-23: 0 rows
  # outside it, so no data cleanup was needed).
  validate :identifier_within_bound, if: :will_save_change_to_pi_mac_address?

  # What a tap box may send as its identifier. Real MACs, and also the short non-MAC identifiers some
  # readers in use send, so there is no format: at most IDENTIFIER_MAX_LENGTH characters after
  # normalization, and no character of Unicode category C (control, format such as bidi overrides and
  # zero-width characters, private use, unassigned, surrogates) or Z (spaces, NBSP included). The one rule for registration (validation below) and for
  # taps (RfidController), so a reader that can be registered can tap, and the identifier that goes into
  # a rate-limit key is bounded.
  IDENTIFIER_MAX_LENGTH = 64

  # "AA-BB-CC-DD-EE-FF " and "aa:bb:cc:dd:ee:ff" are the same reader.
  def self.normalize_mac(raw)
    return nil unless raw.is_a?(String)

    raw.strip.downcase.tr("-", ":").presence
  end

  # The normalized identifier, or nil when it is missing, not a string, too long or has a space,
  # control, format or other non-printing character.
  def self.tap_identifier(raw)
    id = normalize_mac(raw)
    id if id && id.length <= IDENTIFIER_MAX_LENGTH && !id.match?(/[\p{C}\p{Z}]/)
  end

  # Case/separator-insensitive lookup that also matches rows registered before
  # normalization existed (they may be stored upper-case); no data migration needed.
  # When several rows match, one with a space wins over a legacy space-less row.
  def self.find_by_mac(raw)
    mac = normalize_mac(raw)
    return nil unless mac

    where("lower(replace(regexp_replace(pi_mac_address, '^\\s+|\\s+$', '', 'g'), '-', ':')) = ?", mac).order(Arel.sql("space_id IS NULL"), :id).first
  end

  def pi_mac_with_location
    "#{pi_mac_address} (#{pi_location})"
  end

  private

  def normalize_mac_address
    self.pi_mac_address = self.class.normalize_mac(pi_mac_address) || pi_mac_address
  end

  def identifier_within_bound
    return if pi_mac_address.blank? || self.class.tap_identifier(pi_mac_address)

    errors.add(:pi_mac_address, "must be at most #{IDENTIFIER_MAX_LENGTH} characters with no spaces, control or invisible characters")
  end

  def mac_address_not_registered
    errors.add(:pi_mac_address, :taken) if pi_mac_address.present? && self.class.find_by_mac(pi_mac_address)
  end
end
