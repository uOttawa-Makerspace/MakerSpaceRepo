# frozen_string_literal: true

class PiReader < ApplicationRecord
  belongs_to :space, optional: true

  before_validation :normalize_mac_address, on: :create
  validates :pi_mac_address, presence: true, on: :create
  validate :mac_address_not_registered, on: :create

  # "AA-BB-CC-DD-EE-FF " and "aa:bb:cc:dd:ee:ff" are the same reader.
  def self.normalize_mac(raw)
    return nil unless raw.is_a?(String)

    raw.strip.downcase.tr("-", ":").presence
  end

  # Case/separator-insensitive lookup that also matches rows registered before
  # normalization existed (they may be stored upper-case); no data migration needed.
  def self.find_by_mac(raw)
    mac = normalize_mac(raw)
    return nil unless mac

    where("lower(replace(trim(pi_mac_address), '-', ':')) = ?", mac).order(:id).first
  end

  def pi_mac_with_location
    "#{pi_mac_address} (#{pi_location})"
  end

  private

  def normalize_mac_address
    self.pi_mac_address = self.class.normalize_mac(pi_mac_address) || pi_mac_address
  end

  def mac_address_not_registered
    errors.add(:pi_mac_address, :taken) if pi_mac_address.present? && self.class.find_by_mac(pi_mac_address)
  end
end
