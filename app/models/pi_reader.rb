class PiReader < ActiveRecord::Base

  belongs_to :space
  has_many :lab_sessions, dependent: :destroy

  def pi_mac_with_location
    "#{pi_mac_address} (#{pi_location})"
  end
end
