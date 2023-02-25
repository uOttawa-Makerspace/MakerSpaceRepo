# frozen_string_literal: true

class PiReader < ApplicationRecord
  belongs_to :space, optional: true

  def pi_mac_with_location
    "#{pi_mac_address} (#{pi_location})"
  end
end
