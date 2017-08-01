class PiReader < ApplicationRecord
  def pi_mac_with_location
    "#{pi_mac_address} (#{pi_location})"
  end
end
